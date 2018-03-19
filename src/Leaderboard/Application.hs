{-# LANGUAGE DataKinds #-}

module Leaderboard.Application (leaderboard) where

import           Control.Monad.Log   (Logger)
import           Data.Proxy          (Proxy (Proxy))
import           Servant             (Application, Context ((:.), EmptyContext),
                                      enter, serveWithContext)
import           Servant.Auth        (JWT)
import           Servant.Auth.Server (JWT, defaultCookieSettings,
                                      defaultJWTSettings)

import           Leaderboard.API     (LeaderboardAPI, leaderboardServer)
import           Leaderboard.Env     (Env, _envJWK)
import           Leaderboard.Server  (toHandler)

leaderboard :: Env -> Logger () -> Application
leaderboard env logger =
  let
    jwtCfg = defaultJWTSettings (_envJWK env)
    cfg = defaultCookieSettings :. jwtCfg :. EmptyContext
    api = Proxy :: Proxy (LeaderboardAPI '[JWT])
  in
    serveWithContext api cfg $
      enter (toHandler env logger) leaderboardServer
