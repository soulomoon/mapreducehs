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

-- handle the exception here if not receiving the result
-- handle the work through tcp network
runServer :: Chan Context -> Chan Context -> IO ()
runServer cIn cOut = do
  runTCPServer Nothing myPort talk
  where
    talk s = do
      putStrLn "Client connected, sending task:"
      context <- readChan cOut
      sendAll s (encode context)
      -- only wait for the result when the task is valid
      -- otherwise, just send the next task
      when (validWork context)
        (do
          -- should timeout here
          response <- decode <$> recv s 10240
          -- should verify the response and do error handling
          print $ context == response
          writeChan cIn response)


-- from the "network-run" package.
runTCPServer :: Maybe HostName -> ServiceName -> (Socket -> IO a) -> IO a
runTCPServer mhost port server = withSocketsDo $ do
  addr <- resolve
  E.bracket (open addr) close loop
  where
    resolve = do
      let hints =
            defaultHints
              { addrFlags = [AI_PASSIVE],
                addrSocketType = Stream
              }
      head <$> getAddrInfo (Just hints) mhost (Just port)
    open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
      setSocketOption sock ReuseAddr 1
      withFdSocket sock setCloseOnExecIfNeeded
      bind sock $ addrAddress addr
      listen sock 1024
      return sock
    loop sock = forever $
      E.bracketOnError (accept sock) (close . fst) $
        \(conn, _peer) ->
          void $
            -- 'forkFinally' alone is unlikely to fail thus leaking @conn@,
            -- but 'E.bracketOnError' above will be necessary if some
            -- non-atomic setups (e.g. spawning a subprocess to handle
            -- @conn@) before proper cleanup of @conn@ is your case
            forkFinally (server conn) (const $ gracefulClose conn 5000)

-- keep doing work
runClient :: (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> IO ()
runClient mr = do
  b <- goOne mr
  when b $ runClient mr

goOne  :: (Serializable2 k1 v1, Serializable2 k3 v3) => MapReduce k1 v1 k3 v3 -> IO Bool
goOne mr =
  runTCPClient "127.0.0.1" myPort $ \s -> do
  putStrLn "getting"
  msg <- recv s 10240
  -- get the work
  let t = decode msg
  print t
  -- do the work for 1 second
  _ <- threadDelay 100000
  if validWork t
    then runTask @'LocalFileStore mr t >> sendAll s (encode t) >> return True
    else return False

-- from the "network-run" package.
runTCPClient :: HostName -> ServiceName -> (Socket -> IO a) -> IO a
runTCPClient host port client = withSocketsDo $ do
  addr <- resolve
  E.bracket (open addr) close client
  where
    resolve = do
      let hints = defaultHints {addrSocketType = Stream}
      head <$> getAddrInfo (Just hints) (Just host) (Just port)
    open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
      connect sock $ addrAddress addr
      return sock