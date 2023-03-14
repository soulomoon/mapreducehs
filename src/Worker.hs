{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

-- Echo client program
module Main where

import Impl
import ImplWorker
import Core.Type (StoreType(LocalFileStore))

main :: IO ()
-- main = runClientPort runTaskLocalWithDrop myPort sampleReduce 
-- main = runClientPort @'LocalFileStore (runTaskLocalWithDelay @'LocalFileStore  11000000) myPort sampleReduce 
main = runClientPortParallel @'LocalFileStore 5 (runTaskLocal @'LocalFileStore) myPort sampleReduce 