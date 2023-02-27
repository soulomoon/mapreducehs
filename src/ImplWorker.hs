{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleContexts #-}

-- Echo client program
module ImplWorker where

import qualified Control.Exception as E
import Network.Socket
import Network.Socket.ByteString.Lazy (recv, sendAll)
import Data.Binary (decode, encode)
import Core.MapReduceC 
import Core.Serialize (Serializable2)
import Impl
import Core.Store
import Control.Monad.Cont
import Core.Std 
import Core.Type (StoreType(LocalFileStore))
import Core.Logging
import Control.Concurrent.Async (mapConcurrently_)
import Control.Monad.State
import System.Random (randomRIO)
import Control.Exception
import GHC.IO (catchException)

type TaskHandler =  forall k1 v1 k3 v3 context. (Serializable2 k1 v1, Serializable2 k3 v3, MonadStore 'LocalFileStore (StateT context IO), Show context) => MapReduce k1 v1 k3 v3 -> context -> IO ()

-- keep doing work
runClient :: (Serializable2 k1 v1, Serializable2 k3 v3) => TaskHandler -> MapReduce k1 v1 k3 v3 -> IO ()
runClient doWork = runClientPort doWork myPort 


data DropException = DropException deriving (Show)
instance Exception DropException

runClientPort :: (Serializable2 k1 v1, Serializable2 k3 v3) => TaskHandler ->  ServiceName -> MapReduce k1 v1 k3 v3 -> IO ()
runClientPort doWork port mr = do
  b <- catchException (runClientWork doWork port mr) 
    (\DropException -> logg "DropException" >> return True)
  when b $ runClientPort doWork port mr

runClientPortParallel :: (Serializable2 k1 v1, Serializable2 k3 v3) => Int -> TaskHandler ->  ServiceName -> MapReduce k1 v1 k3 v3 -> IO ()
runClientPortParallel n doWork  port mr = mapConcurrently_ (runClientPort doWork port) (replicate n mr)

runTaskLocal :: TaskHandler
runTaskLocal = runTask @'LocalFileStore

runTaskLocalWithDrop :: TaskHandler
runTaskLocalWithDrop m n = do
  i :: Int <- randomRIO (1,10)
  logg $ "dropping task" ++ show n
  if i > 5 then logg "not dropping" >> runTask @'LocalFileStore m n
  else throw DropException

runClientWork  :: (Serializable2 k1 v1, Serializable2 k3 v3) => TaskHandler -> ServiceName -> MapReduce k1 v1 k3 v3 -> IO Bool
runClientWork runT port mr =
  runTCPClient "127.0.0.1" port $ \s -> do
  -- logg "getting"
  msg <- recv s 10240
  -- get the work
  let t = decode msg
  print t
  -- do the work for 1 second
  -- _ <- threadDelay 1000000
  if validWork t
    then runT mr t >> sendAll s (encode t) >> return True
    -- send back and end
    else sendAll s (encode t) >> return False

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