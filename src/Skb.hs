
module Skb where

--   http://stackoverflow.com/questions/14125057/how-to-poke-a-vector-or-to-get-a-ptr-vector-to-its-data
import Foreign.C.Types
import Foreign.C.String
import Foreign.StablePtr
import Data.Word
import Data.Default
import Data.IORef
--
import KeySymbolDefinitions
import State
import Keymap.CustomDvorak
import Modifiers
-- import BitMask

-- https://wiki.haskell.org/Foreign_Function_Interface
-- http://stackoverflow.com/questions/8964362/haskell-stableptr
-- http://stackoverflow.com/questions/14125057/how-to-poke-a-vector-or-to-get-a-ptr-vector-to-its-data
-- https://wiki.haskell.org/Calling_Haskell_from_C
data StateIORef =
  StateIORef (IORef State)

skb_state_new :: CInt -> IO (StablePtr StateIORef)
skb_state_new i = do
  stateIORef <- newIORef (pickInitialState i)
  newStablePtr (StateIORef stateIORef)

skb_state_key_get_one_sym :: StablePtr StateIORef -> KeyCode -> IO Word32
skb_state_key_get_one_sym ptr keycode =
  withState
    ptr
    (\state ->
       let (keySym, _, updatedState) = onKeyCode keycode state
       in  (unKeySymbol keySym, updatedState))

withState :: StablePtr StateIORef -> (State -> (a, State)) -> IO a
withState ptr f = do
  (StateIORef stateIORef) <- deRefStablePtr ptr
  state <- readIORef stateIORef
  let (a, updatedState) = f state
  writeIORef stateIORef updatedState
  return a

skb_state_unref :: StablePtr StateIORef -> IO ()
skb_state_unref = freeStablePtr

pickInitialState :: CInt -> State
pickInitialState 0 = customDvorak
pickInitialState 1 = customDvorakSticky
pickInitialState _ = def

-- skb_state_update_key :: StablePtr StateIORef -> KeyCode -> CKeyDirection -> IO StateComponent
-- the StateComponent is not being used by wlc, so why bother
-- returning it.
skb_state_update_key :: StablePtr StateIORef
                     -> KeyCode
                     -> Word32 -- ^KeyDirection
                     -> IO Word32 -- ^UpdatedStateComponents
skb_state_update_key ptr keycode 0 = -- Released
  withState
    ptr
    ((\(UpdatedStateComponents f,s) -> (f,s)) . onKeyCodeRelease keycode)
skb_state_update_key ptr keycode 1 = -- Pressed
  withState
    ptr
    (\state ->
       let (_, UpdatedStateComponents sc, updatedState) = onKeyCodePress keycode state
       in (sc, updatedState))
skb_state_update_key _ _ _ = return 0

skb_state_update_mask :: StablePtr StateIORef
                      -> Word32
                      -> Word32
                      -> Word32
                      -> Word32
                      -> Word32
                      -> Word32
                      -> IO Word32 -- ^UpdatedStateComponents
skb_state_update_mask ptr depressedModifiers latchedModifiers lockedModifiers depressedGroup latchedGroup lockedGroup =
  withState
        ptr
        (\state ->
            let newState =
                    state
                    { sDepressedModifiers = depressedModifiers
                    , sLatchedModifiers = latchedModifiers
                    , sLockedModifiers = lockedModifiers

                    , sDepressedGroup = depressedGroup
                    , sLatchedGroup = latchedGroup
                    , sLockedGroup = lockedGroup
                    }
            in ((unUpdatedStateComponents (identifyStateChanges state newState), newState)))

skb_keymap_key_repeats :: Word32
                     -> KeyCode
                     -> Word32
skb_keymap_key_repeats keymapIndex keycode =
    (fromIntegral . fromEnum . findIfKeyRepeats keycode . pickInitialState . fromIntegral) keymapIndex

skb_state_serialize_state_component :: StablePtr StateIORef
                      -> Word32
                      -> IO Word32
skb_state_serialize_state_component ptr requestedStateComponent =
  withState
        ptr
        (\state ->
            let value = stateComponent state
                         (UpdatedStateComponents requestedStateComponent)
            in (value, state))

skb_state_key_get_utf :: StablePtr StateIORef
                      -> KeyCode
                      -> IO Word32
skb_state_key_get_utf ptr keyCode =
  withState ptr (keyCodeToUTF keyCode)

-- TODO would have to store modifier index in the keymap/state
skb_keymap_mod_get_index :: Word32 -- KeyMap index used by pickInitialState
                     -> CString
                     -> IO Word32
skb_keymap_mod_get_index _ = fmap modifierIndex . peekCString

-- TODO would have to store modifier index in the keymap/state
skb_keymap_led_get_index :: Word32 -- KeyMap index used by pickInitialState
                     -> CString
                     -> IO Word32
skb_keymap_led_get_index _ = fmap ledIndex . peekCString

