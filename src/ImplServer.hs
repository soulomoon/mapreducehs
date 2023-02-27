-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}

module ImplServer where

import Control.Concurrent (forkFinally, readChan, writeChan, takeMVar, putMVar)
import qualified Control.Exception as E
import Data.Binary (encode, decode)
import Network.Socket
import Network.Socket.ByteString.Lazy (sendAll, recv)
import Control.Monad.State
import Impl
import Core.Type
import Core.Logging
import Control.Exception (try, SomeException, throw)

runServer :: ServerContext -> IO ()
runServer =  runServerPort myPort

-- handle the exception here if not receiving the result
-- handle the work through tcp network
runServerPort :: ServiceName -> ServerContext -> IO ()
runServerPort port sc = do
  runTCPServer Nothing port talk
  where
    talk s = do
      logg "Client connected, sending task:"
      -- critical section ensure only one is reading the task chan
      ss <- takeMVar (serverState sc)
      case ss of 
        Running -> do
          context <- readChan (cOut sc)
          -- critical section 
          -- first one receive the task, should
          -- set the state to stopped to inform other workers
          putMVar (serverState sc) $ if validWork context then Running else Stopped
          res <- try ( do
            sendAll s (encode context)
            -- only wait for the result when the task is valid
            -- otherwise, just send the next task
            -- when (validWork context)
            -- todo should timeout here
            response <- decode <$> recv s 10240
            -- todo should verify the response and do error handling
            logg $ show $ context == response
            return response) 
          case res of
              Right response -> writeChan (cIn sc) response
              Left (ex :: SomeException) -> do
                logg $ show ex
                writeChan (cOut sc) context -- reschedule the task
                throw ex -- now rethrow the exception

        Stopped -> do
          putMVar (serverState sc) ss
          -- send invalid context to inform the worker to stop
          sendAll s (encode invalidContext)
          -- only wait for the result when the task is valid
          -- otherwise, just send the next task
          -- when (validWork context)
          -- todo should timeout here
          response <- decode <$> recv s 10240
          -- todo should verify the response and do error handling
          writeChan (cIn sc) response



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