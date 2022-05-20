{-# LANGUAGE TupleSections #-}

module Core.Util where

import Data.Map hiding (map)

fromMap :: Ord k => Map k [a] -> [(k, a)]
fromMap = foldMapWithKey (\k xs -> map (k,) xs)

toMap :: Ord k => [(k, v)] -> Map k [v]
toMap = fromListWith (++) . map (fmap return)