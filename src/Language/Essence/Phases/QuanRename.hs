{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Language.Essence.Phases.QuanRename where

import Control.Applicative
import Control.Monad ( (<=<) )
import Control.Monad.State ( MonadState, get, put )
import qualified Data.Map as M

import Constants ( isFreshName )
import GenericOps.Core ( GPlate, topDownM, bottomUp )

import Language.Essence.Identifier
import Language.Essence.StructuredVar
import Language.Essence.QuantifiedExpr
import Language.Essence.Phases.InBubbleRename



quanRename :: forall a f m . (GPlate a, Applicative m, MonadState (f,[String]) m) => a -> m a
quanRename = inBubbleRename <=< topDownM worker
    where
        supply :: String -> m (Maybe String)
        supply old = do
            if isFreshName old
                then return Nothing
                else do
                    (f,new:ss) <- get
                    put (f,ss)
                    return (Just new)

        worker :: QuantifiedExpr -> m QuantifiedExpr
        worker p@(QuantifiedExpr {quanVar = Left (Identifier old)}) = do
            mnew <- supply old
            return $ case mnew of
                Nothing  -> p
                Just new -> bottomUp (identifierRenamer old new) p
        worker p@(QuantifiedExpr {quanVar = Right qnSVar}) = do
            let
                rec :: StructuredVar -> m (M.Map String String)
                rec (I (Identifier old)) = do
                    mnew <- supply old
                    return $ case mnew of
                        Nothing  -> M.empty
                        Just new -> M.singleton old new
                rec (STuple  ps) = M.unions <$> mapM rec ps
                rec (SMatrix ps) = M.unions <$> mapM rec ps

            lu <- rec qnSVar

            let f i@(Identifier nm) = case M.lookup nm lu of
                                            Nothing  -> i
                                            Just new -> Identifier new

            return $ bottomUp f p
