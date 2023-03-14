-- {-# LANGUAGE DeriveAnyClass #-}
-- {-# LANGUAGE DeriveGeneric #-}
-- Echo server program
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds #-}

module Main where

import ImplServer
import Core.Type (StoreType(LocalFileStore), Context)
import Impl
import Core.Context (IsContext (invalidContext, initialContext))
import Core.Std (runCtx)



main :: IO ()
main = runCtx (initialContext @Context) $ runMapReduce @'LocalFileStore sample sampleReduce runServer
