-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main where

import ImplServer
import Core.Type (StoreType(LocalFileStore, RedisStore), Context)
import Impl
import Core.Context (IsContext (invalidContext, initialContext))
import Core.Std (runCtx)
import Database.Redis (MonadRedis (liftRedis), unRedis, runRedis, checkedConnect, defaultConnectInfo)
import Control.Monad.State (StateT)
import Control.Monad.Reader (mapReaderT, ReaderT, MonadIO)
import Control.Monad (void)



main :: IO ()
-- main = runCtx (initialContext @Context) $ runMapReduce @'LocalFileStore sample sampleReduce runServer
main = do
    conn <- checkedConnect defaultConnectInfo
    void $ runRedis conn $ runCtx (initialContext @Context) $ runMapReduce @'RedisStore sample sampleReduce runServer

-- instance MonadRedis Redis where
--     liftRedis = id



