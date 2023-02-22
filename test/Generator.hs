{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Generator where 
import Core.Context 
import Core.MapReduceC
import Test.QuickCheck.Arbitrary
import Test.QuickCheck
import Impl ( genContext ) 

newtype MapContextGen = MapContextGen  [[Context]]

instance Arbitrary MapContextGen where 
  arbitrary = do 
    n <- choose (1, 10)
    mr :: MapReduce [Char] [Char] Char Int <- arbitrary
    return $ MapContextGen (genContext n mr)

mapperAdd1 :: Gen ((Char, Int) -> [(Char, Int)])
mapperAdd1  = arbitrary

mapper1 :: Gen ((String, String) -> [(Char, Int)])
mapper1 = arbitrary

reducer :: Gen (Char -> [Int] -> [Int])
reducer = arbitrary

mapId :: Gen ((Char, Int) -> [(Char, Int)])
mapId = arbitrary

instance Arbitrary (MapReduce [Char] [Char] Char Int) where 
    arbitrary = do 
        m1 <- mapper1
        m2 <- mapperAdd1 
        r1 <- reducer
        rest <- arbitrary
        return $ rest :> toM r1 :> toM m2 :> toM m1

instance Arbitrary (MapReduce Char Int Char Int) where
    arbitrary = do 
        x <- mapId
        return $ MrOut :> toM x

