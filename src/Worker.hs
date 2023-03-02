{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}

-- Echo client program
module Main where

import Impl
import ImplWorker

main :: IO ()
-- main = runClientPort runTaskLocalWithDrop myPort sampleReduce 
main = runClientPort (runTaskLocalWithDelay 11000000) myPort sampleReduce 
-- main = runClientPortParallel 5 runTaskLocal myPort sampleReduce 