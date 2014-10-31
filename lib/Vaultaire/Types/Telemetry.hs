{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Vaultaire.Types.Telemetry
     ( TeleResp(..)
     , TeleMsg(..)
     , TeleMsgType(..)
     , AgentID, agentID )
where

import           Control.Applicative
import           Control.Exception
import           Control.Monad
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as B8
import           Data.Monoid
import           Data.Packer
import           Data.Word
import           Test.QuickCheck

import           Vaultaire.Types.Common
import           Vaultaire.Types.TimeStamp
import           Vaultaire.Classes.WireFormat



newtype AgentID = AgentID String
        deriving (Eq, Ord, Monoid)

-- | Response for a telemetry request, sent by the profiler to clients.
data TeleResp = TeleResp
     { _timestamp :: TimeStamp
     , _aid       :: AgentID
     , _msg       :: TeleMsg
     } deriving Eq

-- | The actual telemetric data, reported by Vaultaire worker threads
--   to their profiler.
--
data TeleMsg = TeleMsg
     { _origin  :: Origin
     , _type    :: TeleMsgType
     , _payload :: Word64
     } deriving Eq

-- | Telemetry types. All counts are absolute and all latencies are in microseconds.
data TeleMsgType
   = WriterSimplePoints       -- ^ Total number of simple points written since last message
   | WriterExtendedPoints     -- ^ Total number of extended points written since last message
   | WriterRequest            -- ^ Total number of write requests received since last message
   | WriterRequestLatency     -- ^ Mean latency for one request
   | WriterCephLatency        -- ^ Mean Ceph latency for one request
   | ReaderSimplePoints       -- ^ Total number of simple points read since last message
   | ReaderExtendedPoints     -- ^ Total number of extended points read since last message
   | ReaderRequest            -- ^ Total number of read requests received since last message
   | ReaderRequestLatency     -- ^ Mean latency for one request
   | ReaderCephLatency        -- ^ Mean Ceph latency for one request
   | ContentsEnumerate        -- ^ Total number of enumerate requests received since last message
   | ContentsUpdate           -- ^ Total number of update requests received since last message
   | ContentsEnumerateLatency -- ^ Mean latency for one enumerate request
   | ContentsUpdateLatency    -- ^ Mean latency for one update request
   | ContentsEnumerateCeph    -- ^ Mean Ceph latency for one enumerate request
   | ContentsUpdateCeph       -- ^ Mean Ceph latency for one update request
   deriving (Enum, Bounded, Eq, Ord)


chomp :: ByteString -> ByteString
chomp = B8.takeWhile (/='\0')

-- | An agent ID has to fit in 64 characters and does not contain \NUL.
agentID :: String -> Maybe AgentID
agentID s | length s <= 64 && not (any (=='\0') s)
          = Just $ AgentID s
          | otherwise = Nothing

putAgentID :: AgentID -> Packing ()
putAgentID (AgentID x)
  = putBytes $ B8.pack $ x ++ take (64 - length x) (repeat '\0')

getAgentID :: Unpacking AgentID
getAgentID = AgentID . B8.unpack . chomp <$> getBytes 64

putTeleMsg :: TeleMsg -> Packing ()
putTeleMsg x = do
    -- 8 bytes for the origin.
    let o = unOrigin $ _origin x
    putBytes    $ B8.append o $ B8.pack $ take (8 - B8.length o) $ repeat '\0'
    -- 8 bytes for the message type.
    putWord64LE $ fromIntegral $ fromEnum $ _type x
    -- 8 bytes for the payload
    putWord64LE $ _payload x

getTeleMsg :: Unpacking (Either SomeException TeleMsg)
getTeleMsg = do
    o <- makeOrigin . chomp <$> getBytes 8
    t <- toEnum . fromIntegral <$> getWord64LE
    p <- getWord64LE
    return $ fmap (\org -> TeleMsg org t p) o


instance WireFormat AgentID where
  toWire   = runPacking 64 . putAgentID
  fromWire = tryUnpacking    getAgentID

instance WireFormat TeleMsg where
  toWire   = runPacking 16 . putTeleMsg
  fromWire = runUnpacking getTeleMsg

instance WireFormat TeleResp where
  toWire x = runPacking 96 $ do
    -- 8 bytes for the timestamp
    putWord64LE $ unTimeStamp $ _timestamp x
    -- 64 bytes for the agent ID, padded out with nuls
    putAgentID  $ _aid x
    -- 16 bytes for the message (type and payload)
    putTeleMsg  $ _msg x
  fromWire x = join $ flip tryUnpacking x $ do
    s <- TimeStamp <$> getWord64LE
    a <- getAgentID
    m <- getTeleMsg
    return $ TeleResp s a <$> m


instance Arbitrary TeleMsg where
  arbitrary =   TeleMsg
            <$> arbitrary
            <*> arbitrary
            <*> arbitrary

instance Arbitrary TeleResp where
  arbitrary =   TeleResp
            <$> arbitrary
            <*> arbitrary
            <*> arbitrary

instance Arbitrary TeleMsgType where
  arbitrary = arbitraryBoundedEnum

instance Arbitrary AgentID where
  arbitrary = untilG agentID arbitrary
    where untilG :: (Arbitrary a, Arbitrary b) => (a -> Maybe b) -> Gen a -> Gen b
          untilG f a = a >>= maybe arbitrary return . f


instance Show AgentID where
  show (AgentID s) = s

instance Show TeleMsgType where
  show WriterSimplePoints       = "writer-count-simple-point      "
  show WriterExtendedPoints     = "writer-count-extended-point    "
  show WriterRequest            = "writer-count-request           "
  show WriterRequestLatency     = "writer-latency-request         "
  show WriterCephLatency        = "writer-latency-ceph            "
  show ReaderSimplePoints       = "reader-count-simple-point      "
  show ReaderExtendedPoints     = "reader-count-extended-point    "
  show ReaderRequest            = "reader-count-request           "
  show ReaderRequestLatency     = "reader-latency-request         "
  show ReaderCephLatency        = "reader-latency-ceph            "
  show ContentsEnumerate        = "contents-count-enumerate       "
  show ContentsUpdate           = "contents-count-update          "
  show ContentsEnumerateLatency = "contents-latency-enumerate     "
  show ContentsUpdateLatency    = "contents-latency-update        "
  show ContentsEnumerateCeph    = "contents-latency-ceph-enumerate"
  show ContentsUpdateCeph       = "contents-latency-ceph-update   "
instance Show TeleResp where
  show r = concat [ "teleresp:"
                  , " timestamp=", show $ _timestamp r
                  , " agent="    , show $ _aid r
                  , show $ _msg r ]

instance Show TeleMsg where
  show m = concat [ "origin=" , show $ _origin m
                  , " type="   , show $ _type m
                  , " payload=", show (fromIntegral $ _payload m :: Int) ]