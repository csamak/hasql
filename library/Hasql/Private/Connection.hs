-- |
-- This module provides a low-level effectful API dealing with the connections to the database.
module Hasql.Private.Connection
where

import Hasql.Prelude
import qualified Database.PostgreSQL.LibPQ as LibPQ
import qualified Hasql.Private.PreparedStatementRegistry as PreparedStatementRegistry
import qualified Hasql.Private.IO as IO
import qualified Hasql.Settings as Settings


-- |
-- A single connection to the database.
data Connection =
  Connection !LibPQ.Connection !Bool !PreparedStatementRegistry.PreparedStatementRegistry

-- |
-- Possible details of the connection acquistion error.
type AcquisitionError =
  Maybe ByteString

-- |
-- Acquire a connection using the provided settings encoded according to the PostgreSQL format.
acquire :: Settings.Settings -> IO (Either AcquisitionError Connection)
acquire settings =
  {-# SCC "acquire" #-} 
  runEitherT $ do
    pqConnection <- lift (IO.acquireConnection settings)
    lift (IO.checkConnectionStatus pqConnection) >>= traverse left
    lift (IO.initConnection pqConnection)
    integerDatetimes <- lift (IO.getIntegerDatetimes pqConnection)
    registry <- lift (IO.acquirePreparedStatementRegistry)
    pure (Connection pqConnection integerDatetimes registry)

-- |
-- Release the connection.
release :: Connection -> IO ()
release (Connection pqConnection _ _) =
  LibPQ.finish pqConnection

