module Core.Logging where

import Control.Concurrent (myThreadId)

logg :: String -> IO ()
logg msg = do 
    tid <- myThreadId
    putStrLn $ "[" ++ show tid ++ "]: " ++ msg