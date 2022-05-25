-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}

module Main where

import Control.Concurrent (forkFinally, readChan, Chan, writeChan, writeList2Chan, forkIO, getChanContents, newChan, threadDelay)
import qualified Control.Exception as E
import Data.Binary (encode, decode)
import Network.Socket
import Network.Socket.ByteString.Lazy (sendAll, recv)
import Core.Context 
import Core.MapReduceC
import Control.Monad.State
import Core.Partition
import Impl
import Core.Serialize
import Core.Std
import Core.Store



main :: IO ()
main = do
  let len = pipeLineLength sampleReduce
  putStrLn $ "mr length: " ++ show len
  cIn <- newChan
  cOut <- newChan
  end <- newChan
  let cxt = getContext 5 sampleReduce
  runCtx (Context 5 0 "task" "tempdata" 0) $ sendDataToPartitions @'LocalFileStore sample
  runWorker cIn cOut end cxt
  runCtx (Context 5 len "task" "tempdata" 0) $ sendResult sampleReduce

sendResult :: forall k1 v1 k3 v3 m. (Serializable2 k3 v3, MonadState Context m, MonadIO m) => MapReduce k1 v1 k3 v3 -> m ()
sendResult _ = do
    a <- getAllData @'LocalFileStore
    liftIO $ mapM_ print a
    dd <- getAllDataTup @'LocalFileStore @k3 @v3
    incrTaskId
    sendDataToPartition @'LocalFileStore 0 dd

runWorker ::  Chan Context -> Chan Context -> Chan () -> [[Context]] -> IO ()
runWorker cIn cOut end cxt = do
  _ <- forkIO $ go cxt
  _ <- forkIO $ runServer cIn cOut
  x <- readChan end
  print x
  where 
    go :: [[Context]] -> IO ()
    go [] = writeChan cOut (Context (-1) (-1) "task" "tempdata" (-1)) >> threadDelay 1000 >> writeChan end ()
    go (x:xs) = do 
      putStrLn "putting to chan"
      print x
      writeList2Chan cOut x 
      putStrLn "putting to chan done"
      ys <- take (length x) <$> getChanContents cIn 
      print $ length ys
      go xs


runServer :: Chan Context -> Chan Context -> IO ()
runServer cIn cOut = do 
  runTCPServer Nothing "3000" talk
  where
    talk s = do
      putStrLn "Client connected, sending:"
      context <- readChan cOut
      print context
      sendAll s (encode context)
      -- should timeout here
      response <- decode <$> recv s 10240
      print $ context == response
      writeChan cIn response
      


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