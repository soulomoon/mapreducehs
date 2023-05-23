{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
module Generator where 
import Core.MapReduceC
import Test.QuickCheck.Arbitrary
import Test.QuickCheck
import Impl 
import Control.Concurrent
import Data.List (sort)
import Test.QuickCheck.Monadic (monadicIO, assert, run)
import Network.Socket (ServiceName)
import Core.Logging
import Core.Type
import Core.Context (genContext, IsContext (initialContext))
import Control.Monad.IO.Class (MonadIO(liftIO))
import Core.Std (runCtx)
import ImplServer (ServerRunner(runServer), runServerPort, runServerW)
import Core.Store (MonadStore)
import ImplWorker (runWorker, Worker, ClientType (Single, Multi), Arg, TaskRunnerType)

newtype MapContextGen = MapContextGen  [[Context]]

instance Arbitrary MapContextGen where 
  arbitrary = do 
    n <- choose (1, 10)
    mr :: MapReduce [Char] [Char] Char Int <- arbitrary
    return $ MapContextGen (genContext @Context n $ pipeLineLength mr)

-- mapperAdd1 :: Gen ((Char, Int) -> [(Char, Int)])
-- mapperAdd1  = arbitrary

-- mapper1 :: Gen ((String, String) -> [(Char, Int)])
-- mapper1 = arbitrary

-- reducer :: Gen (Char -> [Int] -> [Int])
-- reducer = arbitrary

-- mapId :: Gen ((Char, Int) -> [(Char, Int)])
-- mapId = arbitrary

instance Arbitrary (MapReduce [Char] [Char] Char Int) where 
    arbitrary = do 
        m1 <- elements [mapper]
        m2 <- elements [mapperAdd1]
        r1 <- elements [reducer]
        return $ MrOut :> toM r1 :> toM m2 :> toM m1

instance Arbitrary (MapReduce Char Int Char Int) where
    arbitrary = do 
        return MrOut 
instance Show (MapReduce [Char] [Char] Char Int) where 
    show _ = "MapReduce"

newtype MRdata = MRdata [([Char], [Char])] deriving Show

instance Arbitrary MRdata where
    arbitrary = do 
        -- v <- elements ["hello", "gogogogogovvv", "opksfasdfdsafa"]
        v <- elements ["hello"]
        return $ MRdata [("", v)]

type RunWorker = (ServiceName -> MapReduce [Char] [Char] Char Int -> IO ())

testServer :: forall (t::StoreType) (c::ClientType) (r :: TaskRunnerType) ctx. (ServerRunner t ctx, Worker t c r, IsContext ctx) 
  => Arg c -> [([Char], [Char])] -> MapReduce [Char] [Char] Char Int -> IO [(Char, Int)]
testServer args dat mr = do
  begin <- newChan
  -- wait for the parent
  _ <- forkIO $ waitSignalWith begin $ runWorker @t @c @r mr args
  sendSignalWith begin $ runServer @t @ctx dat mr 

class DefaultArg a where defaultArg :: Arg a
instance DefaultArg 'Single where defaultArg = "3000"
instance DefaultArg 'Multi where defaultArg = (5, "3000")

testServerProperty :: forall (t::StoreType) (c::ClientType) (r :: TaskRunnerType) ctx.  (DefaultArg c, IsContext ctx, ServerRunner t ctx, Worker t c r) => MRdata -> MapReduce [Char] [Char] Char Int -> Property
testServerProperty (MRdata dat) mr = withMaxSuccess 15 $ monadicIO test
    where test = do 
            a <- run $ sort <$> testServer @t @c @r (defaultArg @c) dat mr
            b <- run $ sort <$> naiveEvaluator dat mr
            run $ logg $ show a
            run $ logg $ show b
            let res = b == a
            run $ logg $ show res
            assert res 

sendSignalWith :: Chan () -> IO b -> IO b
sendSignalWith begin x = do
  writeChan begin ()
  logg "signal sent"
  x
  
waitSignalWith :: Chan a -> IO b -> IO b
waitSignalWith begin x = do
  _ <- readChan begin
  logg "signal received"
  threadDelay 200000
  x