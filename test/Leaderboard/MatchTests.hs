{-# LANGUAGE InstanceSigs        #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Leaderboard.MatchTests
  ( matchTests
  ) where

import           Control.Monad.IO.Class        (MonadIO)
import           Data.Aeson                    (encode)
import qualified Data.Map                      as M
import           Data.Traversable              (sequenceA)
import           Servant.Client                (ClientEnv)

import           Hedgehog                      (Callback (..),
                                                Command (Command),
                                                Concrete (Concrete),
                                                HTraversable (htraverse),
                                                MonadGen, MonadTest, Var (Var),
                                                annotateShow, assert,
                                                evalEither, (===))
import qualified Hedgehog.Gen                  as Gen
import qualified Hedgehog.Range                as Range

import           Test.Tasty                    (TestTree, testGroup)

import           Leaderboard.Gens              (genPlayerWithRsp, genTimestamp, genRegPlayer)
import           Leaderboard.RegistrationTests (cRegister, cRegisterFirst)
import           Leaderboard.SharedState       (LeaderboardState (..),
                                                PlayerMap, PlayerWithRsp (..),
                                                TestMatch (..), checkCommands,
                                                clientToken, emptyState,
                                                successClient, testToRq)
import           Leaderboard.TestClient        (MatchClient (..),mkMatchClient)

matchTests
  :: IO ()
  -> ClientEnv
  -> TestTree
matchTests resetDb env =
  testGroup "match" [
    propMatchTests env resetDb
  ]

genTwoPlayersWithRsps
  :: MonadGen n
  => PlayerMap v
  -> Maybe (n (PlayerWithRsp v, PlayerWithRsp v))
genTwoPlayersWithRsps ps =
  if length ps < 2
  then Nothing
  else Just $ do
    -- Beware the Gen.just here. As long as we've checked we have enough players to satisfy generating
    -- the ids we need, then this should be fine. It's not quite partial, but the generator will fail
    -- if it retries too many times.
    let genPlayerJust = Gen.just . sequenceA . genPlayerWithRsp $ ps
    p1 <- genPlayerJust
    p2 <- Gen.filter ((/= _pwrEmail p1) . _pwrEmail) genPlayerJust
    pure (p1, p2)

genMatch
  :: MonadGen n
  => PlayerMap v
  -> Maybe (n (TestMatch v))
genMatch ps =
  if length ps < 2
  then Nothing
  else do
    genPair <- genTwoPlayersWithRsps ps
    pure $ TestMatch
      <$> fmap (_pwrRsp . fst) genPair
      <*> fmap (_pwrRsp . snd) genPair
      <*> Gen.int (Range.linear 1 100)
      <*> Gen.int (Range.linear 1 100)
      <*> genTimestamp

-- Add a match record. Takes a test record containing ResponsePlayers for the two
-- players who played, and the token of the user adding the match.
data AddMatch (v :: * -> *) =
  AddMatch (TestMatch v) (PlayerWithRsp v)
  deriving (Eq, Show)
instance HTraversable AddMatch where
  htraverse f (AddMatch tm pwr) =
    AddMatch <$> htraverse f tm <*> htraverse f pwr

cAddMatch
  :: ( MonadGen n
     , MonadIO m
     , MonadTest m
     )
  => ClientEnv
  -> Command n m LeaderboardState
cAddMatch env =
  let
    gen (LeaderboardState ps _as _ms) = do
      gMatch <- genMatch ps
      gTokenPlayer <- genPlayerWithRsp ps
      pure $ AddMatch <$> gMatch <*> gTokenPlayer
    exe (AddMatch tm pwr) = do
      let
        rm = testToRq tm
        doAdd = add (mkMatchClient (clientToken pwr)) rm
      annotateShow rm
      annotateShow $ encode rm
      evalEither =<< successClient env doAdd
  in
    Command gen exe [
      -- Need a token, and need a player and their opponent
      Require $ \(LeaderboardState ps _as _ms) _input -> length ps >= 2
    , Require $ \_s (AddMatch TestMatch{..} _p) ->
        _tmPlayer1 /= _tmPlayer2
    , Update $ \(LeaderboardState ps as ms) (AddMatch tm _pwr) vId ->
        LeaderboardState ps as $ M.insert vId tm ms
    , Ensure $ \(LeaderboardState _ps _as msOld) (LeaderboardState _ps' _as' msNew) _in mId -> do
        let vmId = Var (Concrete mId)
        assert $ M.member vmId msNew
        assert $ M.notMember vmId msOld
        length msNew === length msOld + 1
    ]

propMatchTests
  :: ClientEnv
  -> IO ()
  -> TestTree
propMatchTests env reset =
  let
    genRp = const genRegPlayer
  in
    checkCommands "matches" reset emptyState $ ($ env) <$> [cAddMatch, cRegisterFirst genRp, cRegister]
