{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MonoLocalBinds #-}

-- Echo client program
module Core.Client where

import qualified Control.Exception as E
import Network.Socket
import Network.Socket.ByteString.Lazy (recv, sendAll)
import Data.Binary (decode, encode)
import Core.Context
import Control.Monad (when, forM_)
import Core.Signal
import Core.Partition (PartitionConstraint, getDataFromPartition)
import Core.MapReduceC (indexMR, MapReduce)
import Core.Serialize (Serializable2)
import Core.Worker (evalOne)


runWorker :: IO ()
runWorker = do
  t <- getTask
  when (validWork t) $ runTask t >> sendDone t >> runWorker

doTask :: (PartitionConstraint m, Serializable2 k1 v1, Serializable2 k3 v3)  =>
  MapReduce k1 v1 k3 v3 -> m ()
doTask mr = do
      tid <- taskId
      ps <- indexMR tid mr getDataFromPartition
      forM_ ps evalOne

runTask ::  Context -> IO ()
runTask = undefined

validWork :: Context -> Bool
validWork = (> 0) . _taskIdL

sendDone :: Context -> IO ()
sendDone ctx = runTCPClient "127.0.0.1" "3000" $ \s -> do
  sendAll s $ encode ctx

getTask :: IO Context
getTask =
  runTCPClient "127.0.0.1" "3000" $ \s -> do
  msg <- recv s 1024
  return $ decode msg

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