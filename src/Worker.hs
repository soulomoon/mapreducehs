{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}

-- Echo client program
module Main where

import Impl
import ImplWorker
import Core.Type (StoreType(LocalFileStore, RedisStore))
import Control.Monad (void)
import Database.Redis
import Core.Store (MonadStore)
import Control.Monad.State (StateT, MonadIO)
import UnliftIO
import Core.MapReduceC
import Core.Serialize
import Network.Socket (ServiceName)


main :: IO ()
-- main = runClientPort @'LocalFileStore (runTaskLocal @'LocalFileStore) myPort sampleReduce 
-- main = runClientPortParallel @'LocalFileStore 5 (runTaskLocal @'LocalFileStore) myPort sampleReduce 
main = runWorker @'RedisStore @'Multi @'Normal sampleReduce (5, myPort)