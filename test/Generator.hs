{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
module Generator where 
import Core.Context 
import Core.MapReduceC
import Test.QuickCheck.Arbitrary
import Test.QuickCheck
import Impl 
import Test.Tasty (TestTree)
import Test.Tasty.QuickCheck (testProperty)
import Core.Type (StoreType(LocalFileStore))
import Control.Concurrent
import ImplServer
import ImplWorker
import Data.List (sort)
import Test.Tasty.HUnit (assertEqual)
import Test.QuickCheck.Monadic (monadicIO, assert, run)
import Network.Socket (ServiceName)

newtype MapContextGen = MapContextGen  [[Context]]

instance Arbitrary MapContextGen where 
  arbitrary = do 
    n <- choose (1, 10)
    mr :: MapReduce [Char] [Char] Char Int <- arbitrary
    return $ MapContextGen (genContext n mr)

-- mapperAdd1 :: Gen ((Char, Int) -> [(Char, Int)])
-- mapperAdd1  = arbitrary

-- mapper1 :: Gen ((String, String) -> [(Char, Int)])
-- mapper1 = arbitrary

-- reducer :: Gen (Char -> [Int] -> [Int])
-- reducer = arbitrary

-- mapId :: Gen ((Char, Int) -> [(Char, Int)])
-- mapId = arbitrary

instance Arbitrary (MapReduce [Char] [Char] Char Int) where 
    arbitrary = do 
        m1 <- elements [mapper]
        m2 <- elements [mapperAdd1]
        r1 <- elements [reducer]
        return $ MrOut :> toM r1 :> toM m2 :> toM m1

instance Arbitrary (MapReduce Char Int Char Int) where
    arbitrary = do 
        return MrOut 
instance Show (MapReduce [Char] [Char] Char Int) where 
    show _ = "MapReduce"

newtype MRdata = MRdata [([Char], [Char])] deriving Show

instance Arbitrary MRdata where
    arbitrary = do 
        v <- elements ["hello", "gogogogogovvv", "opksfasdfdsafa"]
        return $ MRdata [("", v)]

testServer :: ServiceName -> [([Char], [Char])] -> MapReduce [Char] [Char] Char Int -> IO [(Char, Int)]
testServer port s1 mr = do
  begin <- newChan
  -- wait for the parent
  _ <- forkIO $ waitSignalWith begin $ runClientPort port mr
  sendSignalWith begin $ runMapReduceAndGetResult @'LocalFileStore s1 mr (runServerPort port)



testServerProperty :: MRdata -> MapReduce [Char] [Char] Char Int -> Property
testServerProperty (MRdata dat) mr = withMaxSuccess 5 $ monadicIO test
    where test = do 
            a <- run $ sort <$> testServer "3000" dat mr
            b <- run $ sort <$> naiveEvaluator dat mr
            let res = b == a
            run $ print res
            assert res 

sendSignalWith begin x = do
  writeChan begin ()
  print "signal sent"
  x
  
waitSignalWith begin x = do
  _ <- readChan begin
  print "signal received"
  threadDelay 200000
  x