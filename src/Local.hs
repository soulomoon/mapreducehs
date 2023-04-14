{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}

import Database.Redis
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Reader (ReaderT, ask, runReaderT)
import Control.Monad (void)
import Core.Context
import Core.Type
import Core.Std (runCtx)
import Impl
import ImplServer

type RedisConnection = ReaderT Connection IO

go :: IO ()
go = do 
  -- conn <- checkedConnect defaultConnectInfo
  -- _ <- runRedis conn $ runCtx (initialContext @Context) $ runMapReduce @'RedisStore sample sampleReduce runServer
  -- x <- runRedis conn $ Database.Redis.hset (B.pack "space") (B.pack "test") (B.pack "ok")
  -- print x
  return ()

