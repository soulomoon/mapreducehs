{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
module Generator where 
import Core.MapReduceC
import Test.QuickCheck.Arbitrary
import Test.QuickCheck
import Impl 
import Control.Concurrent
import ImplServer
import Data.List (sort)
import Test.QuickCheck.Monadic (monadicIO, assert, run)
import Network.Socket (ServiceName)
import Core.Logging
import Core.Type
import Core.Context (genContext, IsContext (initialContext))
import Control.Monad.IO.Class (MonadIO(liftIO))
import Core.Std (runCtx)

newtype MapContextGen = MapContextGen  [[Context]]

instance Arbitrary MapContextGen where 
  arbitrary = do 
    n <- choose (1, 10)
    mr :: MapReduce [Char] [Char] Char Int <- arbitrary
    return $ MapContextGen (genContext @Context n $ pipeLineLength mr)

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

type RunWorker = (ServiceName -> MapReduce [Char] [Char] Char Int -> IO ())
testServer :: RunWorker -> ServiceName -> [([Char], [Char])] -> MapReduce [Char] [Char] Char Int -> IO [(Char, Int)]
testServer runWorker port s1 mr = do
  begin <- newChan
  -- wait for the parent
  _ <- forkIO $ waitSignalWith begin $ runWorker port mr
  sendSignalWith begin $ runCtx initialContext $ runMapReduceAndGetResult @'LocalFileStore s1 mr (runServerPort port)

-- test single worker
testServerProperty :: RunWorker -> MRdata -> MapReduce [Char] [Char] Char Int -> Property
testServerProperty runWorker (MRdata dat) mr = withMaxSuccess 15 $ monadicIO test
    where test = do 
            a <- run $ sort <$> testServer runWorker "3000" dat mr 
            b <- run $ sort <$> naiveEvaluator dat mr
            let res = b == a
            run $ logg $ show res
            assert res 

sendSignalWith :: Chan () -> IO b -> IO b
sendSignalWith begin x = do
  writeChan begin ()
  logg "signal sent"
  x
  
waitSignalWith :: Chan a -> IO b -> IO b
waitSignalWith begin x = do
  _ <- readChan begin
  logg "signal received"
  threadDelay 200000
  x