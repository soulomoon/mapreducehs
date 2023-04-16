-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

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
import System.Timeout (timeout)
import Core.Context (validWork, IsContext (invalidContext, initialContext))
import Core.Serialize
import Core.MapReduceC
import Core.Store (MonadStore)
import Core.Std (getResult, runCtx)
import Database.Redis (checkedConnect, defaultConnectInfo, runRedis)

class ServerRunner (t::StoreType) ctx | t -> ctx where
    runServer :: forall k1 v1 k2 v2 . (Serializable2 k1 v1, Serializable2 k2 v2) => [(k1,v1)] -> MapReduce k1 v1 k2 v2 ->  IO ()
    runGetResult :: forall k1 v1 k2 v2 . (Serializable2 k1 v1, Serializable2 k2 v2) => [(k1,v1)] -> MapReduce k1 v1 k2 v2 ->  IO [(k2,v2)]


instance ServerRunner 'LocalFileStore Context where    
  -- run d mr serverRun = runMapReduceAndGetResult @'LocalFileStore d mr serverRun
  runServer d mr = runCtx (initialContext @Context) $ runMapReduce @'LocalFileStore d mr runServerW
  runGetResult d mr = runCtx (initialContext @Context) $ runMapReduceAndGetResult @'LocalFileStore d mr runServerW

instance ServerRunner 'RedisStore Context where    
  -- run d mr serverRun = runMapReduceAndGetResult @'LocalFileStore d mr serverRun
  runServer d mr = do
    conn <- checkedConnect defaultConnectInfo
    void $ runRedis conn $ runCtx (initialContext @Context) $ runMapReduce @'RedisStore d mr runServerW
  runGetResult d mr = do
    conn <- checkedConnect defaultConnectInfo
    runRedis conn $ runCtx (initialContext @Context) $ runMapReduceAndGetResult @'RedisStore d mr runServerW

runServerW :: forall context . (IsContext context) => ServerContext context -> IO ()
runServerW =  runServerPort @context myPort

-- handle the exception here if not receiving the result
-- handle the work through tcp network
runServerPort :: forall context . (IsContext context) => ServiceName -> ServerContext context -> IO ()
runServerPort port sc = do
  runTCPServer Nothing port talk
  where
    talk s = do
      logg "Client connected, sending task:"

      -- critical section ensure only one is reading the task chan
      ss <- takeMVar (serverState sc)
      -- if the server is stopped, just return the invalid context
      context <- (case ss of 
        Running -> readChan (cOut sc)
        Stopped -> return (invalidContext @context))
      -- first one receive the task, should
      -- set the state to stopped to inform other workers
      putMVar (serverState sc) $ if validWork @context context then Running else Stopped
      -- critical section done

      res <- try ( do
        sendAll s (encode context)
        -- only wait for the result when the task is valid
        -- otherwise, just send the next task
        -- when (validWork context)
        -- should timeout here
        -- 10 s = 10000000 us
        -- todo should test if the timeout is working
        response <- timeout (workerTimeout sc) $ decode <$> recv s 10240
        -- todo should verify the response and do error handling
        logg $ show $ Just context == response
        return response) 
      case res of
          Right (Just response) -> writeChan (cIn sc) response
          Right _ -> logg "worker timeout" >> writeChan (cOut sc) context >> throw (userError "worker timeout")
          Left (ex :: SomeException) -> do
            logg $ show ex
            writeChan (cOut sc) context -- reschedule the task
            throw ex -- now rethrow the exception



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