-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MonoLocalBinds #-}

module Main where

import Control.Concurrent (forkFinally, readChan, Chan, writeChan, forkIO)
import qualified Control.Exception as E
import Data.Binary (encode, decode)
import Network.Socket
import Network.Socket.ByteString.Lazy (sendAll, recv)
import Core.Context
import Control.Monad.State
import Impl
import Core.Std
import Core.MapReduceC (naiveEvaluator)
import Core.Logging
import Core.Type

main :: IO ()
main = void $ runMapReduce @'LocalFileStore sample sampleReduce runLocalWorker `execStateT` ctx
  where ctx = Context 5 5 "task" "tempdata" 0

sampleEval :: IO ()
sampleEval = do
  print sample
  x <-  naiveEvaluator sample sampleReduce
  print x
  return ()

-- handle the work locally
runLocalWorker :: ServerContext Context -> IO ()
runLocalWorker sc = do
  context <- liftIO $ readChan (cOut sc)
  runCtx context ( 
    when (validWork context) $ 
      doTask @'LocalFileStore @Context sampleReduce 
      >> liftIO (writeChan (cIn sc) context))
      >> runLocalWorker sc

-- sample worker
runAllWorkers ::  ServerContext Context -> IO ()
runAllWorkers sc = do
  logg "starting workers"
  replicateM_ 5 $ forkIO $ runLocalWorker sc 


-- handle the exception here if not receiving the result
runServer :: Chan Context -> Chan Context -> IO ()
runServer cIn cOut = do
  runTCPServer Nothing "3000" talk
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