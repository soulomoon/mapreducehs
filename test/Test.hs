{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
module Main where

import Test.HUnit (Test(..))

import ImplWorker (runClient, ClientType (Single, Multi), TaskRunnerType (Normal, Drop))
import Test.Tasty
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit
import Generator
import Core.Type (StoreType(LocalFileStore, RedisStore), Context)
import Database.Redis
import Control.Monad (void)
import ImplServer (ServerRunner(runServer))

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
testSingleClient = 
  testGroup "Server with single client" 
  [
    -- testProperty "LocalFileStore" (testServerProperty (runClientPort @'LocalFileStore (runTaskLocal @'LocalFileStore @Context @IO))) 
     testProperty "Redis" (testServerProperty @'RedisStore @'Single @'Normal)
     ,testProperty "LocalFileStore" (testServerProperty @'LocalFileStore @'Single @'Normal)
      -- conn <- checkedConnect defaultConnectInfo
      -- void $ runRedis conn (runClientPort @'RedisStore (runTaskLocal @'RedisStore @Context) port mr)) 
  ]

testMultipleClients :: TestTree
testMultipleClients =  
  testGroup "Server with multiple clients"
  [
     testProperty "LocalFileStore" (testServerProperty @'LocalFileStore @'Multi @'Normal)
     , testProperty "Redis" (testServerProperty @'RedisStore @'Multi @'Normal)
  ]

testClientDrop :: TestTree
testClientDrop = testGroup "Server with clients would drop" 
  [
     testProperty "LocalFileStore" (testServerProperty @'LocalFileStore @'Multi @'Drop)
     , testProperty "LocalFileStore" (testServerProperty @'LocalFileStore @'Single @'Drop)
     , testProperty "Redis" (testServerProperty @'RedisStore @'Multi @'Drop)
     , testProperty "Redis" (testServerProperty @'RedisStore @'Single @'Drop)
  ]

main :: IO ()
main = defaultMain tests
tests :: TestTree
tests = testGroup "Server client test" [
  testSingleClient
  , testMultipleClients
  -- , testClientDrop
  ]

