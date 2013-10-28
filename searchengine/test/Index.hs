import          Data.Monoid
import          Test.Framework
import          Test.Framework.Providers.HUnit
--import          Test.Framework.Providers.QuickCheck2
import          Test.HUnit
--import          Test.QuickCheck
import           Holumbus.Index.TextIndex
import qualified Holumbus.Index.Index                as Ix
import qualified Holumbus.Index.PrefixTreeIndex      as PIx
import qualified Holumbus.Index.ComprPrefixTreeIndex as CPIx
import qualified Holumbus.Index.InvertedIndex        as InvIx
import qualified Holumbus.Index.Proxy.ContextIndex   as ConIx
import           Holumbus.Common.BasicTypes
import           Holumbus.Common.Occurrences         (Occurrences, singleton, Positions)
import           Holumbus.Common.Compression
import           Holumbus.Common.Document            (Document(..))
import qualified Data.Map                            as M


main :: IO ()
main = defaultMainWithOpts
       [ testCase "DmPrefixTree:            insert"        insertTestPIx
       , testCase "InvertedIndex:           insert"        insertTestInvIx
       , testCase "ComprOccPrefixTree:      insert"        insertTestCPIx
       , testCase "ContextIndex Inverted:   insert"        insertTestContextIx
       , testCase "ContextIndex Inverted:   insertContext" insertTestContext
       , testCase "TextIndex:               addWords"      addWordsTest
       ] mempty

{--
 - check if element is inserted in insert operation
 -} 

-- | general check function
insertTest emptyIndex k v = v == nv
  where
  [(_,nv)] = (Ix.search PrefixNoCase k $ Ix.insert k v emptyIndex)

-- | check DmPrefixTree
insertTestPIx :: Assertion
insertTestPIx 
  = True @?= insertTest 
    (Ix.empty::(PIx.DmPrefixTree Positions)) 
    "test" 
    (singleton 1 1)

-- | check ComprOccPrefixTree
insertTestCPIx :: Assertion
insertTestCPIx 
  = True @?= insertTest 
    (Ix.empty::(CPIx.ComprOccPrefixTree CompressedPositions)) 
    "test" 
    (singleton 1 1)

--
-- | check InvertedIndex
insertTestInvIx :: Assertion
insertTestInvIx 
  = True @?= insertTest 
    (Ix.empty::(InvIx.InvertedIndex Occurrences)) 
    "test" 
    (singleton 1 1)

-- | check ContextIndex
insertTestContextIx :: Assertion
insertTestContextIx
  = do
    True @?= newElem == insertedElem
    "context" @?= c
  where
  newElem = singleton 1 1
  [(c,[(_, insertedElem)])] = (ConIx.lookup PrefixNoCase key $ ConIx.insert key newElem emptyIndex)
  key = (Just "context", Just "word")
  emptyIndex :: ConIx.ContextIndex InvIx.InvertedIndex Occurrences
  emptyIndex = ConIx.empty

insertTestContext :: Assertion
insertTestContext = "test" @?= insertedContext
  where
  [insertedContext] = ConIx.keys ix
  ix :: ConIx.ContextIndex InvIx.InvertedIndex Occurrences
  ix = ConIx.insertContext "test" ConIx.empty

{--
 - check helper functions
 -}

addWordsTest :: Assertion
addWordsTest = True @?= length resList == 1
  where
  [(_,resList)] = (ConIx.lookup PrefixNoCase (Just "default", Just "word") $ resIx)
  resIx = addWords (mkWords "default") 1 emptyIndex 
  emptyIndex :: ConIx.ContextIndex InvIx.InvertedIndex Occurrences
  emptyIndex =  ConIx.empty


--
--------------------------------------------------------------------------------------
-- helper
--

mkWordList :: WordList
mkWordList = M.fromList $ [("word", [1,5,10])]

mkWords :: Word -> Words
mkWords w = M.fromList $ [(w, mkWordList)]

mkDoc :: Document
mkDoc = Document "id::1" (M.fromList [("name", "Chris"), ("alter", "30")])


