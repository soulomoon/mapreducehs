{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

-- Echo client program
module Main where

import Impl
import ImplWorker
import Core.Type (StoreType(LocalFileStore, RedisStore))
import Control.Monad (void)
import Database.Redis

main :: IO ()
-- main = runClientPort runTaskLocalWithDrop myPort sampleReduce 
-- main = runClientPort @'LocalFileStore (runTaskLocalWithDelay @'LocalFileStore  11000000) myPort sampleReduce 
-- main = runClientPortParallel @'LocalFileStore 5 (runTaskLocal @'LocalFileStore) myPort sampleReduce 

main = do
    conn <- checkedConnect defaultConnectInfo
    -- void $ runRedis conn $ runClientPortM @'RedisStore (runTaskLocal @'RedisStore  11000000) myPort sampleReduce 
    void $ runRedis conn $ runClientPort @'RedisStore (runTaskLocal @'RedisStore) myPort sampleReduce 