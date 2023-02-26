{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}

-- Echo client program
module Main where

import Impl
import ImplWorker
import Control.Concurrent.Async (mapConcurrently_)

main :: IO ()
main = runClientPortParallel 5 myPort sampleReduce 