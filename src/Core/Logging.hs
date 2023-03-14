module Core.Logging where

import Control.Concurrent (myThreadId)
import Control.Monad.IO.Class (MonadIO (liftIO))

logg :: (MonadIO m) => String -> m ()
logg msg = do 
    tid <- liftIO myThreadId
    liftIO $ putStrLn $ "[" ++ show tid ++ "]: " ++ msg