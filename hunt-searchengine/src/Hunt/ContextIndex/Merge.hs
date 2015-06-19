{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Hunt.ContextIndex.Merge where

import           Control.Applicative
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import           Data.Monoid
import           Data.Set (Set)
import qualified Data.Set as Set

import           Hunt.ContextIndex.Segment
import           Hunt.ContextIndex.Types
import           Hunt.DocTable (DocTable)
import           Hunt.Index.Schema
import           Hunt.Utility

newtype MergeLock
  = MergeLock (Set SegmentId)
  deriving (Eq, Monoid)

data MergePolicy
  = MergeAll
  deriving (Eq, Show)

newtype Merge m dt
  = Merge { runMerge :: m (MergeResult dt) }

data MergeResult dt
  = MergeResult { mrModIxx      :: ContextIndex dt -> ContextIndex dt
                , mrReleaseLock :: MergeLock -> MergeLock
                }

data TryMerge m dt
  = TryMerge !MergeLock !(Merge m dt)

data MergeEnv dt
  = MergeEnv { mePolicy   :: !MergePolicy
             , meSchema   :: !Schema
             , meSegments :: ![Segment dt]
             }

type MergeM dt m a = ReaderT (MergeEnv dt) m a

-- TODO: does this make sense? CLEANUP!
-- | Returns a `TryMerge` action. Since merging itself can be costly `tryMerge`
--   returns a monadic action which can be executed asynchronously. It returns
--   an idempotent function which can be used to modify the `ContextIndex`
--   afterwards to make the merged segment visible and to delete old segments.
--   Bundled with  the action there is a `MergeLock` which is used
--   to ensure different merges don't touch non exclusive `Segment`s. Simply
--   pass an empty `MergeLock` if you don't own one yet.
tryMerge :: (Monad m, MonadIO n, DocTable dt)
            => MergeLock -> ContextIndex dt -> m (TryMerge n dt)
tryMerge (MergeLock lock) ixx
  = do segments <- selectSegments 1 10 (filterSet lock (ciSegments ixx))
       return undefined



{-
    segs <- selectSegments MergeAll (filterSet lock (ciSegments ixx))
       case segs of
        [] -> return (TryMerge (MergeLock lock) (Merge (return (MergeResult id id))))
        sx -> do
          let env   = MergeEnv MergeAll (ciSchema ixx) sx
              sids  = Set.fromList [sid | s <- sx, let sid = segId s  ]
              lock' = MergeLock (sids `mappend` lock)
          return (TryMerge lock' (Merge (runReaderT doMerge env)))
-}

doMerge :: (MonadIO m, DocTable dt) => MergeM dt m (MergeResult dt)
doMerge
  = do sx        <- asks meSegments
       schema    <- asks meSchema
       segments' <- doMerge' schema 10 sx

       return MergeResult { mrModIxx = \ixx -> ixx
                          , mrReleaseLock = \lock -> lock
                          }

doMerge' :: (MonadIO m, DocTable dt)
         => Schema
         -> Int
         -> [Segment dt]
         -> m [Segment dt]
doMerge'
  = go 1
  where
    go sz s mf segs
      = do (eqSzed, rest) <- selectSegments sz mf segs
           case eqSzed of
             [] -> return segs
             _  -> do
               ns <- foldM1' (mergeSegments s) eqSzed
               go (sz * mf) s mf (ns:rest)

selectSegments :: (Monad m, DocTable dt)
               => Int
               -> Int
               -> [Segment dt]
               -> m [Segment dt]
selectSegments sz mf segs
  = do levels <- segLevels segs
       let (maxLvl, _) = Map.findMax levels
           bottomLvl   = maxLvl - 0.75
           (l, r)      = Map.partitionWithKey(\lvl _ -> lvl <= bottomLvl) levels
       return (Map.elems l, Map.elems r)
  where
    logBase' b a
      = logBase (fromIntegral b) (fromIntegral a)

    segLevels segs
      = do xs <- mapM (\s -> do ss <- segmentSize s
                                return (logBase' mf ss , s)
                      ) segs
           return (Map.fromList xs)

filterSet :: Set SegmentId -> [Segment dt] -> [Segment dt]
filterSet sx
  = List.filter (\s -> Set.notMember (segId s) sx)
