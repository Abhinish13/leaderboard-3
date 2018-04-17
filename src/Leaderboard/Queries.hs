module Leaderboard.Queries
  ( selectOrPersistJwk
  , selectPlayerCount
  , addPlayer
  ) where

import           Control.Lens
import           Crypto.JOSE                (JWK)
import           Data.Aeson                 (eitherDecode')
import           Data.Text.Lazy             (fromStrict)
import           Data.Text.Lazy.Encoding    (encodeUtf8)
import qualified Database.Beam              as B
import           Database.PostgreSQL.Simple (Connection)

import           Leaderboard.Schema         (Player, leaderboardDb, _jwkJwk,
                                             _leaderboardJwk)
import           Leaderboard.Types          (LeaderboardError (JwkDecodeError, MultipleJwksInDb),
                                             RegisterPlayer)

withDb =
  B.withDatabaseDebug putStrLn

selectOrPersistJwk
  :: Connection
  -> IO JWK
  -> IO (Either LeaderboardError JWK)
selectOrPersistJwk conn newJwk = do
  jwks <- selectJwks conn
  case jwks of
    Left s      -> pure . Left $ JwkDecodeError
    Right []    -> insertJwk conn newJwk
    Right [jwk] -> pure $ Right jwk
    Right jwks  -> pure . Left . MultipleJwksInDb $ jwks

selectJwks
  :: Connection
  -> IO (Either String [JWK])
selectJwks conn = do
  jwks <-
    withDb conn .
    B.runSelectReturningList .
    B.select $
      B.all_ (_leaderboardJwk leaderboardDb)
  pure $ traverse (eitherDecode' . encodeUtf8 . fromStrict . _jwkJwk) jwks

insertJwk
  :: Connection
  -> IO JWK
  -> IO (Either LeaderboardError JWK)
insertJwk =
  undefined

selectPlayerCount
  :: Connection
  -> IO Integer
selectPlayerCount =
  undefined

addPlayer
  :: RegisterPlayer
  -> m Player
addPlayer =
  undefined
