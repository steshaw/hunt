{-# LANGUAGE RecordWildCards #-}
module Hunt.SegmentIndex where

import           Hunt.Common.ApiDocument            (ApiDocument)
import qualified Hunt.SegmentIndex.IndexWriter      as IndexWriter
import           Hunt.SegmentIndex.Types
import           Hunt.SegmentIndex.Types.SegmentId
import           Hunt.SegmentIndex.Types.SegmentMap (SegmentMap)
import qualified Hunt.SegmentIndex.Types.SegmentMap as SegmentMap

import           Control.Concurrent.STM
import           Data.Map                           (Map)
import qualified Data.Map.Strict                    as Map
import qualified System.Directory                   as Directory

-- | Create new 'SegmentIndex' at the given index directory.
newSegmentIndex :: FilePath
                -> IO SegIxRef
newSegmentIndex indexDir = do

  -- TODO: bail out if index directory contains an index
  Directory.createDirectoryIfMissing True indexDir

  segIdGen <- newSegIdGen
  siRef    <- newTMVarIO $! SegmentIndex { siIndexDir = indexDir
                                         , siSegIdGen = segIdGen
                                         , siSchema   = Map.empty
                                         , siSegments = SegmentMap.empty
                                         , siSegRefs  = SegmentMap.empty
                                         }

  return siRef

-- | Fork a new 'IndexWriter' from a 'SegmentIndex'. This is very cheap
-- and never fails.
newIndexWriter :: SegIxRef
               -> IO IxWrRef
newIndexWriter sigRef = atomically $ do
  si@SegmentIndex{..} <- takeTMVar sigRef

  ixwr <- newTMVar $! IndexWriter {
      iwIndexDir    = siIndexDir
    , iwNewSegId    = genSegId siSegIdGen
    , iwSchema      = siSchema
    , iwSegments    = siSegments
    , iwNewSegments = SegmentMap.empty
    , iwSegIxRef    = sigRef
    }

  putTMVar sigRef $! si {
        siSegRefs = SegmentMap.unionWith (+)
                    (SegmentMap.map (\_ -> 1) siSegments)
                    siSegRefs
      }

  return ixwr

insertDocuments :: IxWrRef -> [ApiDocument] -> IO ()
insertDocuments ixwrref docs = do
  ixwr  <- atomically $ takeTMVar ixwrref
  ixwr' <- IndexWriter.insertList docs ixwr
  atomically $ putTMVar ixwrref $! ixwr'

closeIndexWriter :: IxWrRef -> IO ()
closeIndexWriter ixwrref = atomically $ do
  ixwr  <- takeTMVar ixwrref
  segix <- takeTMVar (iwSegIxRef ixwr)

  case IndexWriter.close ixwr segix of
    Right segix' -> putTMVar (iwSegIxRef ixwr) segix'
    Left err -> undefined -- FIXME:
