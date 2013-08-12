-- ----------------------------------------------------------------------------

{- |
  Module     : Holumbus.Index.HashedCompactDocuments
  Copyright  : Copyright (C) 2012 Uwe Schmidt
  License    : MIT

  Maintainer : Uwe Schmidt (uwe@fh-wedel.de)
  Stability  : experimental

  Like Holumbus.Index.HashedDocuments but using CompressedDoc directly.
  Conversion and exposing the Document interface is done by a proxy DocTable
  with newConvValueDocTable.
-}

-- ----------------------------------------------------------------------------

module Holumbus.DocTable.HashedCompactDocuments
    (
      -- * Documents type
      Documents (..)
    , CompressedDoc(..)
    , DocMap

      -- * Construction
    , emptyDocTable

      -- * Conversion
    , fromMap

    --, toDocument
    --, fromDocument
    , fromDocMap
    , toDocMap
    )
where

import qualified Codec.Compression.BZip         as BZ

import           Control.DeepSeq
import           Control.Arrow                  (second)

import           Data.Binary                    (Binary)
import qualified Data.Binary                    as B
import           Data.Set                       (Set)
import qualified Data.Set                       as S

import           Data.ByteString.Lazy           (ByteString)
import qualified Data.ByteString.Lazy           as BS

import           Data.Digest.Murmur64

import           Holumbus.Index.Common
import qualified Holumbus.Index.Common.DocIdMap as DM

import           Holumbus.DocTable.DocTable     hiding (map)

import           Holumbus.Utility               ((.::))

-- ----------------------------------------------------------------------------

-- | The table which is used to map a document to an artificial id and vice versa.

type DocMap
    = DocIdMap CompressedDoc

newtype CompressedDoc
    = CDoc { unCDoc :: ByteString }
      deriving (Eq, Show)

newtype Documents
    = Documents { idToDoc   :: DocMap }     -- ^ A mapping from a document id to
                                            --   the document itself.
      deriving (Eq, Show, NFData)

-- ----------------------------------------------------------------------------

-- | An empty document table.

emptyDocTable :: DocTable (DocTable Documents CompressedDoc) Document
emptyDocTable = newConvValueDocTable toDocument fromDocument emptyDocTableCompressed

emptyDocTableCompressed :: DocTable Documents CompressedDoc
emptyDocTableCompressed = newDocTable emptyDocuments

-- | The hash function from URIs to DocIds
docToId :: URI -> DocId
docToId = mkDocId . fromIntegral . asWord64 . hash64 . B.encode


fromMap :: DocIdMap CompressedDoc -> DocTable Documents CompressedDoc
fromMap = newDocTable . fromMap'

-- ----------------------------------------------------------------------------

newDocTable :: Documents -> DocTable Documents CompressedDoc
newDocTable i =
    Dt
    {
      -- | Test whether the doc table is empty.
      _null                          = nullDocs' i

    -- | Returns the number of unique documents in the table.
    , _size                          = sizeDocs' i

    -- | Lookup a document by its id.
    , _lookup                        = lookupById' i

    -- | Lookup the id of a document by an URI.
    , _lookupByURI                   = lookupByURI' i

    -- | Union of two disjoint document tables. It is assumed, that the DocIds and the document uris
    -- of both indexes are disjoint. If only the sets of uris are disjoint, the DocIds can be made
    -- disjoint by adding maxDocId of one to the DocIds of the second, e.g. with editDocIds
    , _union                         = newDocTable . unionDocs' i . impl

    -- | Test whether the doc ids of both tables are disjoint.
    , _disjoint                      = disjointDocs' i . impl

    -- | Insert a document into the table. Returns a tuple of the id for that document and the
    -- new table. If a document with the same URI is already present, its id will be returned
    -- and the table is returned unchanged.
    , _insert                        = second newDocTable . insert' i

    -- | Update a document with a certain DocId.
    , _update                        = newDocTable .:: updateDoc' i

    -- | Removes the document with the specified id from the table.
    , _delete                        = newDocTable . deleteById' i

    -- | Deletes a set of Docs by Id from the table.
    , _difference                    = \ids -> newDocTable $ differenceById' ids i

    {-
    -- | Deletes a set of Docs by Uri from the table. Uris that are not in the docTable are ignored.
    deleteByUri                   :: Set URI -> d -> d
    deleteByUri us ds             = deleteById idSet ds
      where
      idSet = catMaybesSet . S.map (lookupByURI ds) $ us
    -}

    -- | Update documents (through mapping over all documents).
    , _map                           = \f -> newDocTable $ updateDocuments' f i

    , _filter                        = \f -> newDocTable $ filterDocuments' f i

    -- | Convert document table to a single map
    , _toMap                         = toMap' i

    -- | Edit document ids
    , _editDocIds                    = \f -> newDocTable $ editDocIds' f i

    -- | The doctable implementation.
    , _impl                          = i
    }

-- ----------------------------------------------------------------------------

toDocument                      :: CompressedDoc -> Document
toDocument                      = B.decode . BZ.decompress . unCDoc

fromDocument                    :: Document -> CompressedDoc
fromDocument                    = CDoc . BZ.compress . B.encode

{-
mapDocument                     :: (Document -> Document) -> CompressedDoc -> CompressedDoc
mapDocument f                   = fromDocument . f . toDocument
-}

toDocMap                        :: DocIdMap Document -> DocMap
toDocMap                        = DM.map fromDocument

fromDocMap                      :: DocMap -> DocIdMap Document
fromDocMap                      = DM.map toDocument

-- ----------------------------------------------------------------------------

nullDocs' :: Documents -> Bool
nullDocs'
    = DM.null . idToDoc

sizeDocs' :: Documents -> Int
sizeDocs'
    = DM.size . idToDoc

lookupById' :: Monad m => Documents -> DocId -> m CompressedDoc
lookupById'  d i
    = maybe (fail "") return
      . DM.lookup i
      . idToDoc
      $ d

lookupByURI' :: Monad m => Documents -> URI -> m DocId
lookupByURI' d u
    = maybe (fail "") (const $ return i)
      . DM.lookup i
      . idToDoc
      $ d
      where
        i = docToId u

disjointDocs' :: Documents -> Documents -> Bool
disjointDocs' dt1 dt2
    = DM.null $ DM.intersection (idToDoc dt1) (idToDoc dt2)

unionDocs' :: Documents -> Documents -> Documents
unionDocs' dt1 dt2
    | disjointDocs' dt1 dt2
        = unionDocsX dt1 dt2
    | otherwise
        = error
          "HashedDocuments.unionDocs: doctables are not disjoint"

insert' :: Documents -> CompressedDoc -> (DocId, Documents)
insert' ds d
    = maybe reallyInsert (const (newId, ds)) (lookupById' ds newId)
      where
        newId
            = docToId . uri . toDocument $ d
        reallyInsert
            = rnf d `seq`                    -- force document compression
              (newId, Documents {idToDoc = DM.insert newId d $ idToDoc ds})

updateDoc' :: Documents -> DocId -> CompressedDoc -> Documents
updateDoc' ds i d
    = rnf d `seq`                    -- force document compression
      Documents {idToDoc = DM.insert i d $ idToDoc ds}

deleteById' :: Documents -> DocId -> Documents
deleteById' ds d
    = Documents {idToDoc = DM.delete d $ idToDoc ds}

-- XXX: EnumMap does not have a fromSet function so that you can use fromSet (const ()) and ignore the value
differenceById' :: Set DocId -> Documents -> Documents
differenceById' s ds
    = Documents {idToDoc = idToDoc ds `DM.difference` (DM.fromAscList . map mkKeyValueDummy . S.toList $ s)}
    where
    mkKeyValueDummy k = (k, undefined) -- XXX: strictness properties of EnumMap?

updateDocuments' :: (CompressedDoc -> CompressedDoc) -> Documents -> Documents
updateDocuments' f d
    = Documents {idToDoc = DM.map f (idToDoc d)}

filterDocuments' :: (CompressedDoc -> Bool) -> Documents -> Documents
filterDocuments' p d
    = Documents {idToDoc = DM.filter p (idToDoc d)}

fromMap' :: DocIdMap CompressedDoc -> Documents
fromMap' itd
    = Documents {idToDoc = itd}

toMap' :: Documents -> DocIdMap CompressedDoc
toMap'
    = idToDoc

-- default implementations

editDocIds' :: (DocId -> DocId) -> Documents -> Documents
editDocIds' f                  = fromMap' . DM.foldrWithKey (DM.insert . f) DM.empty . toMap'

-- ----------------------------------------------------------------------------

instance Binary Documents where
    put = B.put . idToDoc
    get = fmap Documents B.get

-- ------------------------------------------------------------

instance Binary CompressedDoc where
    put = B.put . unCDoc
    get = B.get >>= return . CDoc

-- ----------------------------------------------------------------------------

instance NFData CompressedDoc where
    rnf (CDoc s)
        = BS.length s `seq` ()

-- ------------------------------------------------------------

-- | Create an empty table.
emptyDocuments :: Documents
emptyDocuments
    = Documents DM.empty


unionDocsX :: Documents -> Documents -> Documents
unionDocsX dt1 dt2
    = Documents
      { idToDoc = idToDoc dt1 `DM.union` idToDoc dt2 }

{-
-- | Create a document table containing a single document.
singleton :: Document -> Documents
singleton d
    = rnf d' `seq`
      Documents {idToDoc = DM.singleton (docToId . uri $ d) d'}
    where
      d' = fromDocument d
      -}
