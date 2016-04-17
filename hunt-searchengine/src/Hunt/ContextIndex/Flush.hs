{-# LANGUAGE BangPatterns              #-}
{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE ExistentialQuantification #-}
module Hunt.ContextIndex.Flush(
    runFlush
  , FlushPolicy(..)
  ) where

import           Hunt.Common.Document (Document)
import           Hunt.Common.DocId (DocId)
import qualified Hunt.Common.DocIdSet as DocIdSet
import           Hunt.ContextIndex.Types
import           Hunt.ContextIndex.Types.SegmentMap (SegmentId)
import qualified Hunt.ContextIndex.Types.SegmentMap as SegmentMap
import           Hunt.DocTable (DocTable, DValue)
import qualified Hunt.DocTable as DocTable
import           Hunt.ContextIndex.Segment (Docs, Segment (..), Kind(..))
import qualified Hunt.ContextIndex.Segment as Segment
import qualified Hunt.ContextIndex.Documents as Docs

import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LByteString
import           Data.ByteString.Builder (hPutBuilder)
import           Data.ByteString.Builder.Prim ((>*<))
import qualified Data.ByteString.Builder.Prim as Builder
import           Control.Monad
import           Control.Monad.IO.Class
import qualified Data.Binary as Binary
import qualified Data.Binary.Get as Binary
import qualified Data.Binary.Put as Binary

import           Data.Word
import           System.FilePath
import           System.IO
import qualified Data.Vector.Unboxed as UVector
import qualified Data.Vector.Unboxed.Mutable as UMVector

-- | Runs a `Flush` and writes files to the index directory. This operation is atomic.
runFlush :: (MonadIO m, Binary.Binary (DValue Docs)) =>
            FlushPolicy -> SegmentId -> Segment 'Frozen -> m (ContextIndex -> ContextIndex)
runFlush policy sid seg = do
  !dix <- writeDocTable policy sid seg
  return $ \ixx ->
    ixx { ciSegments = SegmentMap.insertWith (\_ s ->
                                                s { segDocs = Docs.DtIxed (readDocument policy sid) dix
                                                  }) sid seg (ciSegments ixx)
        }

readDocument :: FlushPolicy -> SegmentId -> Word64 -> Word64 -> IO Document
readDocument policy sid offset size = do
  h <- openFile (fpFlushDirectory policy </> show sid <.> "dt") ReadMode
  hSeek h AbsoluteSeek (fromIntegral offset)
  lbs <- LByteString.hGet h (fromIntegral size)
  let !doc = Binary.runGetOrFail Binary.get lbs
  case doc of
    Left err -> print err >> return undefined
    Right (_, _, doc') -> do doc' `seq` hClose h
                             return doc'

writeDocTable :: (MonadIO m, Binary.Binary (DValue Docs)) =>
                 FlushPolicy -> SegmentId -> Segment 'Frozen -> m Docs.DocTableIndex
writeDocTable policy sid seg = liftIO $ do

  withFile dtIxFile WriteMode $ \ix -> do
    withFile dtDocFile WriteMode $ \docs -> do

      hSetBinaryMode ix True
      hSetBuffering ix (BlockBuffering Nothing)

      hSetBinaryMode docs True
      hSetBuffering docs (BlockBuffering Nothing)

      -- Don't access DocTable directly, as it could be an already
      -- flushed Segment so we don't clutter memory
      docIds <- Segment.segmentDocIds seg

      -- A vector representation for our new new DocTable index.
      -- We use two vectors, one for the strictly ordered DocIds
      -- and one for the (offset, size) info for the disk seek.
      let numDocs = DocIdSet.size docIds
      mDtIx <- UMVector.unsafeNew numDocs

      foldM_ (\(!offset, !i) did -> do
                 Just doc <- Segment.lookupDocument did seg

                 let docEntry = Binary.runPut (Binary.put doc)
                     size     = fromIntegral $ LByteString.length docEntry
                     dixEntry = Builder.word64BE >*< Builder.word64BE

                 hPutBuilder ix $ Builder.primFixed dixEntry (offset, size)
                 LByteString.hPut docs docEntry

                 UMVector.unsafeWrite mDtIx i (did, offset, size)

                 return (offset + size, i + 1)
                 ) (0, 0) (DocIdSet.toList docIds)

      hFlush ix
      hFlush docs

      dtIx <- UVector.unsafeFreeze mDtIx
      return (Docs.DTI dtIx)
  where
    dtIxFile = fpFlushDirectory policy </> show sid <.> "dix"
    dtDocFile = fpFlushDirectory policy </> show sid <.> "dt"
