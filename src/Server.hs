-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FunctionalDependencies #-}

module Main where

import ImplServer
import Core.Type (StoreType(LocalFileStore, RedisStore), Context, ServerContext)
import Impl
import Core.Context (IsContext (invalidContext, initialContext))
import Core.Std (runCtx, getResult)
import Database.Redis (MonadRedis (liftRedis), unRedis, runRedis, checkedConnect, defaultConnectInfo)
import Control.Monad.State (StateT)
import Control.Monad.Reader (mapReaderT, ReaderT, MonadIO)
import Control.Monad (void)
import Core.Serialize
import Core.MapReduceC
import Core.Store (MonadStore)


main :: IO ()
main = void $ runServer @'RedisStore sample sampleReduce 






