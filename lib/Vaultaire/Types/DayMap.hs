--
-- Copyright © 2013-2014 Anchor Systems, Pty Ltd and Others
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the 3-clause SD licence.
--

{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Vaultaire.Types.DayMap
(
    DayMap(..)
) where

import Control.Applicative
import Control.Exception
import Control.Monad
import Data.ByteString (ByteString)
import qualified Data.ByteString as S
import Data.List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Monoid
import Data.Packer
import Test.QuickCheck
import Vaultaire.Classes.WireFormat
import Vaultaire.Types.Common


newtype DayMap = DayMap { unDayMap :: Map Epoch NumBuckets }
    deriving (Monoid, Eq)

instance Show DayMap where
    show = intercalate "\n"
         . map (\(k,v) -> show k ++ "," ++ show v)
         . Map.toAscList
         . unDayMap

instance Arbitrary DayMap where
    -- Valid first entry followed by whatever
    arbitrary =
        DayMap . Map.fromList . ((0, 128):) <$> arbitrary

instance WireFormat DayMap where
    fromWire bs
        | S.null bs =
            Left . toException . userError $ "empty daymap file"
        | S.length bs `rem` 16 /= 0 =
            Left . toException . userError $ "corrupt contents, should be multiple of 16"
        | otherwise =
            let loaded = mustLoadDayMap bs
                (first, _) = Map.findMin (unDayMap loaded)
            in if first == 0
                then Right loaded
                else Left . toException . userError $ "bad first entry, must start at zero."

    toWire (DayMap m)
        | Map.null m = error "cannot toWire empty DayMap"
        | otherwise =
            runPacking (Map.size m * 16) $
                forM_ (Map.toAscList m)
                      (\(k,v) -> putWord64LE k >> putWord64LE v)


mustLoadDayMap :: ByteString -> DayMap
mustLoadDayMap =
    DayMap . Map.fromList . runUnpacking parse
  where
    parse = many $ (,) <$> getWord64LE <*> getWord64LE
