{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}

module Core.Server where

import Control.Concurrent (forkFinally, readChan, Chan)
import qualified Control.Exception as E
import Control.Monad (forever, void)
import Data.Binary (encode)
import Network.Socket
import Network.Socket.ByteString.Lazy (sendAll)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.RWS (MonadReader)
import Core.Context

-- server that returns task to workers
runServer :: Chan Context -> IO ()
runServer c = do 
  runTCPServer Nothing "3000" $ talk
  where
    talk s = do
      context <- readChan c
      sendAll s (encode context)


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