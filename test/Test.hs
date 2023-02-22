{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
module Main where

import Test.HUnit (Test(..), runTestTTAndExit)
import Core.Type (StoreType(LocalFileStore))
import Impl (runMapReduce)

import Control.Concurrent (forkFinally, readChan, Chan, writeChan, forkIO, threadDelay, newChan)
import qualified Control.Exception as E
import Data.Binary (encode, decode)
import Network.Socket
import Network.Socket.ByteString.Lazy (sendAll, recv)
import Core.Context
import Control.Monad.State
import Impl
import Core.Serialize
import Core.MapReduceC
import Core.Std (runTask)
import Data.List (sort)
import ImplWorker (runClient)
import ImplServer (runServer)
import Test.Tasty
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit

foo :: Int -> (Int, Int)
foo 3 = (1, 2)
foo _ = (0, 0)

partA :: Int -> IO (Int, Int)
partA _ = pure (5, 3) -- change to (5,3) if you want the tests to succeed

partB :: Int -> IO Bool
partB x = pure (x == 3)

sendSignalWith begin x = do
  writeChan begin ()
  print "signal sent"
  x
  
waitSignalWith begin x = do
  _ <- readChan begin
  print "signal received"
  threadDelay 200000
  x
  

sample1 :: [([Char], [Char])]
sample1 = [("", "hello")]

testServer :: [([Char], [Char])] -> MapReduce [Char] [Char] Char Int -> IO [(Char, Int)]
testServer s1 mr = do
  begin <- newChan
  -- wait for the parent
  _ <- forkIO $ waitSignalWith begin $ runClient mr
  sendSignalWith begin $ runMapReduceAndGetResult @'LocalFileStore s1 mr runServer


test1, test2 :: Test
test1 = TestCase $ do
  a <- sort <$> testServer sample1 sampleReduce
  b <- sort <$> naiveEvaluator sample1 sampleReduce
  assertEqual "testServer" b a
-- test1 = TestCase $ assertEqual "for (foo 3)," (1 :: Integer) (1 :: Integer)
test2 = TestCase $ do
  (x, y) <- partA 3
  assertEqual "for the first result of partA," 5 x
  b <- partB y
  assertBool ("(partB " ++ show y ++ ") failed") b

main :: IO ()
main = runTestTTAndExit (TestList [TestLabel "test1" test1])
