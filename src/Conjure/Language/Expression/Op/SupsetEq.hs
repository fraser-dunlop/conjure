{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, DeriveFunctor, DeriveTraversable, DeriveFoldable #-}

module Conjure.Language.Expression.Op.SupsetEq where

import Conjure.Prelude
import Conjure.Language.Expression.Op.Internal.Common
import Conjure.Language.Expression.Op.SubsetEq


data OpSupsetEq x = OpSupsetEq x x
    deriving (Eq, Ord, Show, Data, Functor, Traversable, Foldable, Typeable, Generic)

instance Serialize x => Serialize (OpSupsetEq x)
instance Hashable  x => Hashable  (OpSupsetEq x)
instance ToJSON    x => ToJSON    (OpSupsetEq x) where toJSON = genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpSupsetEq x) where parseJSON = genericParseJSON jsonOptions

instance BinaryOperator (OpSupsetEq x) where
    opLexeme _ = L_supsetEq

instance (TypeOf x, Pretty x) => TypeOf (OpSupsetEq x) where
    typeOf (OpSupsetEq a b) = sameToSameToBool a b

instance (Pretty x, TypeOf x) => DomainOf (OpSupsetEq x) x where
    domainOf op = mkDomainAny ("OpSupsetEq:" <++> pretty op) <$> typeOf op

instance EvaluateOp OpSupsetEq where
    evaluateOp (OpSupsetEq a b) = evaluateOp (OpSubsetEq b a)

instance SimplifyOp OpSupsetEq x where
    simplifyOp _ = na "simplifyOp{OpSupsetEq}"

instance Pretty x => Pretty (OpSupsetEq x) where
    prettyPrec prec op@(OpSupsetEq a b) = prettyPrecBinOp prec [op] a b
