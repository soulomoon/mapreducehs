-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}

module Main where

import ImplServer
import Core.Type (StoreType(LocalFileStore))
import Impl
import Control.Monad (void)


main :: IO ()
main = void $ runMapReduce @'LocalFileStore sample sampleReduce runServer
