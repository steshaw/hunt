{-# LANGUAGE DeriveTraversable          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TypeFamilies               #-}
module Hunt.SegmentIndex.Types.SegmentMap (
    module Hunt.SegmentIndex.Types.SegmentMap
  , index
  , lookupDefault
  , adjust
  , replace

  , forWithKey
  , forWithKey_
  , forWithKeyM
  , forWithKeyM_
  ) where

import           Hunt.SegmentIndex.Types.SegmentId

import           Data.IntMap.Strict                (IntMap)
import qualified Data.IntMap.Strict                as IM
import           Data.Key

-- | A map indexed by 'SegmentId'.
newtype SegmentMap a = SM { unSM :: IntMap a }
                     deriving ( Functor, Keyed, Zip, ZipWithKey
                              , Lookup, Indexable, Adjustable
                              , FoldableWithKey, Foldable
                              , Traversable )

type instance Key SegmentMap = SegmentId

instance TraversableWithKey SegmentMap where
  traverseWithKey f (SM im) =
    SM <$> IM.traverseWithKey (\k v -> f (SegmentId k) v) im

null :: SegmentMap a -> Bool
null = IM.null . unSM

empty :: SegmentMap a
empty = SM IM.empty

insert :: SegmentId -> a -> SegmentMap a -> SegmentMap a
insert (SegmentId k) v (SM m) = SM (IM.insert k v m)

map :: (a -> b) -> SegmentMap a -> SegmentMap b
map f (SM m) = SM (IM.map f m)

unionWith :: (a -> a -> a) -> SegmentMap a -> SegmentMap a -> SegmentMap a
unionWith f (SM m1) (SM m2) = SM (IM.unionWith f m1 m2)

intersectionWith :: (a -> b -> c)
                 -> SegmentMap a
                 -> SegmentMap b
                 -> SegmentMap c
intersectionWith f (SM m1) (SM m2) = SM (IM.intersectionWith f m1 m2)

difference :: SegmentMap a -> SegmentMap b -> SegmentMap a
difference (SM m1) (SM m2) = SM (IM.difference m1 m2)
