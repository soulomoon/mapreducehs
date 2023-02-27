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

main :: IO ()
main = runClientPortParallel 5 runTaskLocal myPort sampleReduce 