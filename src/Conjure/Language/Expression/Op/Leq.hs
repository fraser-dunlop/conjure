{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, DeriveFunctor, DeriveTraversable, DeriveFoldable #-}

module Conjure.Language.Expression.Op.Leq where

import Conjure.Prelude
import Conjure.Language.Expression.Op.Internal.Common


data OpLeq x = OpLeq x x
    deriving (Eq, Ord, Show, Data, Functor, Traversable, Foldable, Typeable, Generic)

instance Serialize x => Serialize (OpLeq x)
instance Hashable  x => Hashable  (OpLeq x)
instance ToJSON    x => ToJSON    (OpLeq x) where toJSON = genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpLeq x) where parseJSON = genericParseJSON jsonOptions

instance BinaryOperator (OpLeq x) where
    opLexeme _ = L_Leq

instance (TypeOf x, Pretty x) => TypeOf (OpLeq x) where
    typeOf (OpLeq a b) = sameToSameToBool a b

instance (Pretty x, TypeOf x) => DomainOf (OpLeq x) x where
    domainOf op = mkDomainAny ("OpLeq:" <++> pretty op) <$> typeOf op

instance EvaluateOp OpLeq where
    evaluateOp (OpLeq x y) = return $ ConstantBool $ x <= y

instance SimplifyOp OpLeq x where
    simplifyOp _ = na "simplifyOp{OpLeq}"

instance Pretty x => Pretty (OpLeq x) where
    prettyPrec prec op@(OpLeq a b) = prettyPrecBinOp prec [op] a b