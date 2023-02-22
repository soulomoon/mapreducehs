{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
module Main where

import Test.HUnit
import Core.Type (StoreType(LocalFileStore))
import Impl (runMapReduce)

import Control.Concurrent (forkFinally, readChan, Chan, writeChan, forkIO, threadDelay)
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

foo :: Int -> (Int, Int)
foo 3 = (1, 2)
foo _ = (0, 0)

partA :: Int -> IO (Int, Int)
partA _ = pure (5, 3) -- change to (5,3) if you want the tests to succeed

partB :: Int -> IO Bool
partB x = pure (x == 3)

testServer ::  MapReduce [Char] [Char] Char Int -> IO [(Char, Int)]
testServer mr = do
  -- wait for the parent
  _ <- forkIO $ threadDelay 2000000 >> runClient mr
  runMapReduceAndGetResult @'LocalFileStore mr runServer


test1, test2 :: Test
test1 = TestCase $ do
  a <- sort <$> testServer sampleReduce
  b <- sort <$> naiveEvaluator sample sampleReduce
  assertEqual "testServer" b a
-- test1 = TestCase $ assertEqual "for (foo 3)," (1 :: Integer) (1 :: Integer)
test2 = TestCase $ do
  (x, y) <- partA 3
  assertEqual "for the first result of partA," 5 x
  b <- partB y
  assertBool ("(partB " ++ show y ++ ") failed") b

main :: IO ()
main = runTestTTAndExit (TestList [TestLabel "test1" test1])
