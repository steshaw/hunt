{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverlappingInstances       #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

module Hunt.Index.Proxy.KeyIndex
( KeyProxyIndex(..)
)
where

import           Control.DeepSeq
import           Prelude                                 as P

import           Control.Applicative                     ((<$>))
import           Control.Arrow                           (first)
import           Control.Monad

import           Data.Bijection
import           Data.Binary                             (Binary (..))

import           Hunt.Index.Index
import qualified Hunt.Index.Index                    as Ix

import           Hunt.Index.Proxy.CompressedIndex

import           Hunt.Common.Occurrences.Compression

-- ----------------------------------------------------------------------------

newtype KeyProxyIndex from impl cv
    = KPIx { kpIx :: impl cv}
    deriving (Eq, Show, NFData)

mkKPIx :: impl cv -> KeyProxyIndex from impl cv
mkKPIx v = KPIx $! v

-- ----------------------------------------------------------------------------

instance Binary (impl v) => Binary (KeyProxyIndex from impl v) where
    put = put . kpIx
    get = get >>= return . mkKPIx

-- ----------------------------------------------------------------------------

instance Index (KeyProxyIndex from impl) where
    type IKey      (KeyProxyIndex from impl) v = from
    type IVal      (KeyProxyIndex from impl) v = IVal impl v
    type ICon      (KeyProxyIndex from impl) v =
        ( Index impl
        , ICon impl v
        , Bijection from (IKey impl v)
        )

    insert k v (KPIx i)
        = liftM mkKPIx $ insert (to k) v i

    batchDelete ks (KPIx i)
        = liftM mkKPIx $ batchDelete ks i

    empty
        = mkKPIx $ empty

    fromList l
        = liftM mkKPIx . fromList $ P.map (first to) l

    toList (KPIx i)
        = liftM (first from <$>) $ toList i

    search t k (KPIx i)
        = liftM (first from <$>) $ search t (to k) i

    lookupRange k1 k2 (KPIx i)
        = liftM (first from <$>) $ lookupRange (to k1) (to k2) i

    unionWith op (KPIx i1) (KPIx i2)
        = liftM mkKPIx $ unionWith op i1 i2

    map f (KPIx i)
        = liftM mkKPIx $ Ix.map f i

    keys (KPIx i)
        = liftM (P.map from) $ keys i


-- special instance for a CompressedOccurrences proxy within a TextKey proxy
-- This requires XFlexibleInstances
-- This requires XOverlappingInstances since the previous instance definition is more generic
-- TODO: can this be somehow generalized to a genric index containing a compression proxy?
instance Index (KeyProxyIndex from (ComprOccIndex impl to)) where
    type IKey      (KeyProxyIndex from (ComprOccIndex impl to)) v = from
    type IVal      (KeyProxyIndex from (ComprOccIndex impl to)) v = IVal      (ComprOccIndex impl to) v
    type ICon      (KeyProxyIndex from (ComprOccIndex impl to)) v =
        ( Index (ComprOccIndex impl to)
        , ICon  (ComprOccIndex impl to) v
        , Bijection from (IKey (ComprOccIndex impl to) v)
        )
    -- this is the only "special" function
    batchDelete docIds (KPIx (ComprIx pt))
        = liftM (mkKPIx . mkComprIx) $ Ix.map (differenceWithKeySet docIds) pt

    -- everything below is copied from the more general instance Index (KeyProxyIndex impl)
    insert k v (KPIx i)
        = liftM mkKPIx $ insert (to k) v i

    empty
        = mkKPIx $ empty

    fromList l
        = liftM mkKPIx . fromList $ P.map (first to) l

    toList (KPIx i)
        = liftM (first from <$>) $ toList i

    search t k (KPIx i)
        = liftM (first from <$>) $ search t (to k) i

    lookupRange k1 k2 (KPIx i)
        = liftM (first from <$>) $ lookupRange (to k1) (to k2) i

    unionWith op (KPIx i1) (KPIx i2)
        = liftM mkKPIx $ unionWith op i1 i2

    map f (KPIx i)
        = liftM mkKPIx $ Ix.map f i

    keys (KPIx i)
        = liftM (P.map from) $ keys i