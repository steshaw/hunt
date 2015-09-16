{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Hunt.ContextIndex.Types where

import           Hunt.Common.SegmentMap (SegmentId, SegmentMap)
import           Hunt.Index.Schema (Schema)
import           Hunt.Segment (Segment)

import           Data.Aeson
import           Data.Binary
import           Data.Typeable

-- | A number representing the version of the index
newtype Revision = Revision Int
  deriving (Binary, Enum, Eq, FromJSON, ToJSON, Ord, Show, Typeable)

-- | The actual index type.
data ContextIndex dt
  = ContextIndex { ciSegments      :: !(SegmentMap (Segment dt))
                 , ciSchema        :: !Schema
                 , ciNextSegmentId :: !SegmentId
                 }

-- | TODO: remove dummy instance
instance Binary (ContextIndex dt) where
  get = undefined
  put = undefined
