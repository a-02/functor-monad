{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances #-}
-- | 'Applicative' functor transformers, like monad transformers, for free.
module Control.Applicative.Trans.FreeAp(
    ApT(..),
    
    toFree, fromFree,
    
    transApT, hoistApT,
    liftF, liftT, appendApT,
    
    foldApT, foldApT_,
    fjoinApTLeft, fjoinApTRight
) where

import Control.Applicative
import Data.Functor.Identity
import qualified Control.Applicative.Free as Free

-- | @'ApT' f@ is a \"free\" \"applicative transformer\", in the same sense
--   @'Control.Monad.Trans.Free.FreeT' f@ is a free monad transformer.
--
--   ==== \"Applicative transformer\"
--   
--   Being an \"applicative transformer\" means these two things:
--
--   * Applying @ApT f@ to an applicative functor @g@ constructs a new applicative
--     functor @ApT f g@.
--   
--   * Using 'liftT', you can lift an action of @g@ to the action of @ApT f g@.
--
--       > liftT :: g x -> ApT f g x
--       
--       'liftT' is an applicative transformation. In other words, @liftT@ preserves
--       'pure' and @'<*>'@:
--         
--       > liftT (pure x) = pure x
--       > liftT (x <*> y) = liftT x <*> liftT y
--   
--   ==== \"Free\" applicative transformer
--
--   It's the \"free\" applicative transformer. It means @ApT f g@ is the special, the most universal
--   one among various applicative functors which can lift @f@ and @g@ into them.
-- 
--   * @ApT f g@ has a way to lift any value of @f a@ into an action of @ApT f g a@.
-- 
--       > liftF :: (Applicative g) => f a -> ApT f g a
--     
--       Because @ApT f g@ is also an applicative transformer on @g@, it has a way to lift @g@ too.
--
--       > liftT :: g x -> ApT f g x
-- 
--   * Suppose another applicative functor @h@ is capable of lifting both @f@ and @g@ to @h@.
--
--       > fh :: f a -> h a
--       > gh :: g a -> h a
--
--       @ApT f g@ is the universal applicative among them. There's 'foldApT' to construct
--       the applicative transformation from @ApT f g@ to @h@, without losing how to lift @f@ and @g@.
--
--       > foldApT :: forall f g h x. Applicative h => (forall a. f a -> h a) -> (forall a. g a -> h a) -> ApT f g x -> h x
--       >
--       > foldApT fh gh :: forall x. ApT f g x -> h x
--       >
--       > foldApT fh gh . liftF = fh
--       > foldApT fh gh . liftT = gh
--
--   * @ApT f g@ contains no extra data that are not from lifting @f@ and/or @g@ then combining them together
--     by @Applicative@ operation '<*>'.
--
--       It means any applicative transformation @run :: forall a. ApT f g a -> h a@ which satisfies @run . liftF = fh@ and @run . liftT = gh@
--       is equivalent to @foldApT fh gh@.
data ApT f g x =
      PureT (g x)
    | forall a b c. ApT (a -> b -> c -> x) (g a) (f b) (ApT f g c)

instance Functor g => Functor (ApT f g) where
    fmap h (PureT gx) = PureT $ fmap h gx
    fmap h (ApT x ga fb rc) = ApT (\a b c -> h (x a b c)) ga fb rc 
    
    x <$ PureT gx = PureT (x <$ gx)
    x <$ ApT _ ga fb rc = ApT (\_ _ _ -> x) ga fb rc

instance Applicative g => Applicative (ApT f g) where
    pure = PureT . pure
    PureT gx <*> PureT gy = PureT (gx <*> gy)
    PureT gx <*> ApT y ga fb rc = ApT (\ ~(x,a) b c -> x (y a b c)) (liftA2 (,) gx ga) fb rc
    ApT x ga fb rc <*> rest = ApT (\a b ~(c,y) -> x a b c y) ga fb (liftA2 (,) rc rest)

    PureT gx *> PureT gy = PureT (gx *> gy)
    PureT gx *> ApT y ga fb rc = ApT y (gx *> ga) fb rc
    ApT _ ga fb rc *> rest = ApT  (\_ _ y -> y) ga fb (rc *> rest)

    PureT gx <* PureT gy = PureT (gx <* gy)
    PureT gx <* ApT _ ga fb rc = ApT (\x _ _ -> x) (gx <* ga) fb rc
    ApT x ga fb rc <* rest = ApT x ga fb (rc <* rest)

-- | When the base applicative is 'Identity', @ApT f Identity@ is the free applicative 'Free.Ap'.
toFree :: ApT f Identity a -> Free.Ap f a
toFree = toFreeAux id

toFreeAux :: (a -> b) -> ApT f Identity a -> Free.Ap f b
toFreeAux k (PureT (Identity a)) = Free.Pure (k a)
toFreeAux k (ApT x (Identity a) fb rc) = Free.Ap fb (toFreeAux (\c b -> k (x a b c)) rc)

fromFree :: Free.Ap f a -> ApT f Identity a
fromFree (Free.Pure a) = PureT (Identity a)
fromFree (Free.Ap fb rest) = ApT flip (Identity id) fb (fromFree rest)

-- | Lift an applicative transformation @(forall a. g a -> g' a)@ to
--   an applicative transformation @(forall b. ApT f g b -> ApT f g' b)@.
hoistApT :: (forall a. g a -> g' a) -> ApT f g b -> ApT f g' b
hoistApT phi (PureT gx) = PureT (phi gx)
hoistApT phi (ApT x ga fb rc) = ApT x (phi ga) fb (hoistApT phi rc)

-- | Lift any natural transformation @(forall a. f a -> f' a)@ to
--   an applicative transformation @(forall b. ApT f g b -> ApT f' g b)@.
transApT :: (forall a. f a -> f' a) -> ApT f g b -> ApT f' g b
transApT _ (PureT gx) = PureT gx
transApT phi (ApT x ga fb rc) = ApT x ga (phi fb) (transApT phi rc)

-- | Lift an applicative action @g x@ to @ApT f g x@
liftT :: g x -> ApT f g x
liftT = PureT

-- | Lift an uninterpreted action @f x@ to @ApT f g x@
liftF :: Applicative g => f x -> ApT f g x
liftF fx = ApT (\_ x _ -> x) (pure ()) fx (pure ())

-- | Equivalent to the following definition, but is faster and doesn't require @Applicative g@ constraint.
--   
--   @appendApT x prefix fb postfix = x \<$\> prefix \<*\> liftF fb \<*\> postfix@
appendApT :: (a -> b -> c -> x) -> ApT f g a -> f b -> ApT f g c -> ApT f g x
appendApT x prefix fb postfix = case prefix of
    PureT ga -> ApT x ga fb postfix
    ApT a ga' fb' prefix' -> ApT  (\a' b' ~(c',b,c) -> x (a a' b' c') b c) ga' fb' (appendApT (,,) prefix' fb postfix)

-- | Interpret @ApT f g@ into an applicative @h@.
--   
--   When @g@ is an @Applicative@ and @gh :: forall a. g a -> h a@ is an applicative transformation,
--   @'foldApT' fh gh@ is an applicative transformation too.
--
--   @foldApT@ satisfy the following equations with 'liftF' and 'liftT'.
--
--   > foldApT fh gh . liftF = fh
--   > foldApT fh gh . liftT = gh
foldApT :: forall f g h x. Applicative h => (forall a. f a -> h a) -> (forall a. g a -> h a) -> ApT f g x -> h x
foldApT f2h g2h = go
  where
    go :: forall y. ApT f g y -> h y
    go (PureT gx) = g2h gx
    go (ApT x ga fb rc) = liftA3 x (g2h ga) (f2h fb) (go rc)

-- | Perform a monoidal analysis over @ApT f g@ value.
--
--   This is equivalent to use @foldApT@ with the applicative @'Control.Applicative.Const' m@,
--   except @m@ doesn't need to be a @Monoid@ but just a @Semigroup@.
foldApT_ :: forall f g m x. Semigroup m => (forall a. f a -> m) -> (forall a. g a -> m) -> ApT f g x -> m
foldApT_ f2m g2m = go
  where
    go :: forall y. ApT f g y -> m
    go (PureT gx) = g2m gx
    go (ApT _ ga fb rc) = g2m ga <> f2m fb <> go rc

-- | Collapsing @ApT@ nested left-to-right.
fjoinApTLeft :: forall f g x. ApT f (ApT f g) x -> ApT f g x
fjoinApTLeft = go
  where
    go :: forall y. ApT f (ApT f g) y -> ApT f g y
    go (PureT inner) = inner
    go (ApT y inner fb rest) = appendApT y inner fb (go rest)

-- | Collapsing @ApT@ nested right-to-left.
fjoinApTRight :: Applicative g => ApT (ApT f g) g x -> ApT f g x
fjoinApTRight = foldApT id liftT
