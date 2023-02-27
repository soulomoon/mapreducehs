{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
module Main where

import Test.HUnit (Test(..))

import ImplWorker (runClientPort, runClientPortParallel, runTaskLocal, runTaskLocalWithDrop)
import Test.Tasty
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit
import Generator

foo :: Int -> (Int, Int)
foo 3 = (1, 2)
foo _ = (0, 0)

partA :: Int -> IO (Int, Int)
partA _ = pure (5, 3) -- change to (5,3) if you want the tests to succeed

partB :: Int -> IO Bool
partB x = pure (x == 3)

sample1 :: [([Char], [Char])]
sample1 = [("", "hello")]

test2 :: Test
-- test1 = TestCase $ do
--   a <- sort <$> testServer sample1 sampleReduce
--   b <- sort <$> naiveEvaluator sample1 sampleReduce
--   assertEqual "testServer" b a
-- test1 = TestCase $ assertEqual "for (foo 3)," (1 :: Integer) (1 :: Integer)
test2 = TestCase $ do
  (x, y) <- partA 3
  assertEqual "for the first result of partA," 5 x
  b <- partB y
  assertBool ("(partB " ++ show y ++ ") failed") b

-- a = quickCheckWith stdArgs { maxSuccess = 5000 } 

testSingleClient :: TestTree
testSingleClient = testProperty "Server with single client" (testServerProperty (runClientPort runTaskLocal))

testMultipleClients :: TestTree
testMultipleClients = testProperty "Server with multiple clients" (testServerProperty (runClientPortParallel 5 runTaskLocal))

testClientDrop :: TestTree
testClientDrop = testProperty "Server with clients would drop" (testServerProperty (runClientPortParallel 5 runTaskLocalWithDrop))

main :: IO ()
main = defaultMain tests
tests :: TestTree
tests = testGroup "Server client test" [testSingleClient, testMultipleClients, testClientDrop]

