{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE Rank2Types       #-}
module Main where

import Grav2ty.Simulation
import Grav2ty.Control

import Control.Lens
import Linear.V2
import Data.Fixed (mod')
import Data.Maybe
import Data.Tuple (uncurry)
import qualified Data.Map as Map
import Data.Map.Lens
import Text.Printf

import Graphics.Gloss
import Graphics.Gloss.Data.ViewPort
import Graphics.Gloss.Interface.Pure.Game

data GlossState
  = GlossState
  { _glossViewPort :: (Int, Int)
  , _glossViewPortCenter :: (Float, Float)
  , _glossViewPortScale :: Float
  , _glossCenterView :: Bool
  } deriving (Show, Eq, Ord)

makeLenses ''GlossState

vectorToPoint :: V2 a -> (a, a)
vectorToPoint (V2 x y) = (x, y)

homBimap :: Bifunctor f => (a -> b) -> f a a -> f b b
homBimap f = bimap f f

renderHitbox :: Hitbox Float -> Picture
renderHitbox box =  Color white $
  case box of
    HCircle (V2 x' y') r -> translate x' y' $ Circle r
    HLine a b -> Line . map vectorToPoint $ [a, b]
    HCombined boxes -> Pictures $ map renderHitbox boxes

renderObject :: Object Float -> Picture
renderObject obj = renderHitbox . realHitbox $ obj

renderUi :: (PrintfArg a, Num a) => State a GlossState -> Picture
renderUi state = (uncurry translate) (homBimap ((+ 50) . (* (-1)) . (/ 2) . fromIntegral)
  . view (graphics . glossViewPort) $ state)
  . scale 0.2 0.2 . Color green . Text $ uiText
  where uiText = printf "Acceleration: %.0f TimeScale: %.1f Tick: %d" acc timeScale tick
        acc = fromMaybe 0 $ state^?control.ctrlInputs.at LocalMod ._Just.modAcc
        timeScale = state^.control.ctrlTimeScale
        tick = state^.control^.ctrlTick

renderStars :: (Float, Float) -> Picture
renderStars center = undefined

renderGame :: State Float GlossState -> Picture
renderGame state = Pictures [ renderUi  state, applyViewPort objs ]
  where objs = Pictures . map renderObject $ state^.world
        applyViewPort = if state^.graphics . glossCenterView
                           then applyViewPortToPicture viewport
                           else id
        viewport = ViewPort
          (homBimap negate $ state^.graphics.glossViewPortCenter)
          0
          (state^.graphics.glossViewPortScale)

boundSub :: (Ord a, Num a) => a -> a -> a -> a
boundSub min a x = if res < min then min else res
  where res = x - a

boundAdd :: (Ord a, Num a) => a -> a -> a -> a
boundAdd max a x = if res > max then max else res
  where res = x + a

eventHandler :: (Show a, Ord a, Real a, Floating a) => Event
             -> State a GlossState -> State a GlossState
eventHandler (EventKey key Down _ _) state = action state
  where updateLocalMod :: Lens' (Modification a) b -> (b -> b)
                       -> State a GlossState -> State a GlossState
        updateLocalMod l f = over (control.ctrlInputs.at LocalMod ._Just.l) f
        accStep = 1
        rotStep = pi / 10
        scaleStep = 0.05
        timeStep = 0.2
        mod2pi = flip mod' (2 * pi)
        action =
          case key of
            SpecialKey KeyUp -> updateLocalMod modAcc (+ accStep)
            SpecialKey KeyDown -> updateLocalMod modAcc (boundSub 0 accStep)
            SpecialKey KeyLeft -> updateLocalMod modRot (mod2pi . (+ rotStep))
            SpecialKey KeyRight -> updateLocalMod modRot (mod2pi . (subtract rotStep))
            SpecialKey KeySpace -> updateLocalMod modFire (const $ state^.control.ctrlTick + 10)
            Char 'c' -> over (graphics.glossCenterView) not
            Char '+' -> over (graphics.glossViewPortScale) (+ scaleStep)
            Char '-' -> over (graphics.glossViewPortScale) (subtract scaleStep)
            Char '.' -> over (control.ctrlTimeScale) (+ timeStep)
            Char ',' -> over (control.ctrlTimeScale) (boundSub 0 timeStep)
            _ -> id
eventHandler (EventResize vp) state = set (graphics.glossViewPort) vp state
eventHandler _ s = s

updateWorld :: Float -> State Float GlossState -> State Float GlossState
updateWorld ts state = updateState ts extract state
  where extract obj@Dynamic { objectMod = LocalMod } = set
          (graphics.glossViewPortCenter)
          (vectorToPoint . objectLoc $ obj)
        extract _ = id

initialWorld :: Fractional a => State a GlossState
initialWorld = State
  (ControlState (Map.fromList [(LocalMod, zeroModification)]) 1 0)
  (GlossState (800, 800) (0, 0) 1 True)
  [ Dynamic shipHitbox 0 10000 (V2 200 0) (V2 0 0) (V2 0 0) LocalMod (Just (V2 15 0, V2 1 0))
  , Dynamic (centeredCircle 10) 0 5000 (V2 0 200) (V2 15 0) (V2 0 0) NoMod Nothing
  , Static (centeredCircle 80) 0 moonMass (V2 0 0)
--  , Static (centeredCircle 40) 0 (0.5 * moonMass) (V2 250 250)
  ]
  where moonMass = 8e14

main :: IO ()
main = play
  (InWindow "grav2ty" (initialWorld^.graphics.glossViewPort) (0,0))
  black
  300
  initialWorld
  renderGame
  eventHandler
  updateWorld
