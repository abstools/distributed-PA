
{-# LANGUAGE NoImplicitPrelude, ExistentialQuantification,
  MultiParamTypeClasses, ScopedTypeVariables, FlexibleContexts,
  PartialTypeSignatures, LambdaCase, OverloadedStrings, TemplateHaskell #-}
{-# OPTIONS_GHC
  -w -Werror -fforce-recomp -fwarn-missing-methods -fno-ignore-asserts#-}
module DisPAck (main) where


import ABS.Runtime.Base
import ABS.Runtime.Prim (findWoken, while, get, (<$!>), null, nullFuture',awaitBool',(<..>))
import ABS.Runtime.Extension.Promise
import ABS.Runtime.Extension.IO
import ABS.Runtime.CmdOpt
import Control.Monad.Trans.Cont (evalContT, callCC)
import qualified Data.IntMap as IM (empty, lookup, delete, insert, notMember)
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Distributed.Process (Process, spawn, spawnLocal, receiveWait, match, matchIf, matchSTM, send, expect, ProcessId,getSelfPid)
import Control.Distributed.Process.Node
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Backend.SimpleLocalnet
import ABS.Runtime.TQueue (TQueue (..), newTQueueIO, writeTQueue, readTQueue)
import Control.Concurrent.STM (atomically, readTVar, readTVarIO, writeTVar)    
import Control.Applicative ((<$))
import Control.Concurrent (forkIO)
import Prelude (($))
import qualified Control.Monad.IO.Class as I' (liftIO)
import Data.List ((++))
import Control.Monad ((>>=),(>>))

import ABS.StdLib
--import ABS.Runtime
import Data.Function ((.))
import Control.Applicative ((<*>), (*>))
import Control.Monad ((=<<))
import qualified Control.Applicative as I' (pure)
import qualified Data.IORef as I'
       (newIORef, readIORef, writeIORef, atomicModifyIORef')
import qualified Control.Monad.Trans.Class as I' (lift)
import qualified Control.Monad as I' (when, sequence, join)
import qualified Prelude as I'
       (IO, Eq, Ord(..), Show(..), undefined, error, negate, fromIntegral,
        mapM_)
import qualified Unsafe.Coerce as I' (unsafeCoerce)
import qualified Control.Concurrent as I' (ThreadId)
import qualified Control.Concurrent.MVar as I'
       (isEmptyMVar, readMVar)
import Control.Exception (assert)
import qualified Control.Exception as I'
       (Exception(..), SomeException, throwTo, throw)
-- import qualified Data.Dynamic as I' (toDyn, fromDynamic)
-- import qualified Data.Map as I' (lookup)
-- import qualified Web.Scotty as I' (get, param, json, raise)
-- import qualified ABS.StdLib as I' (put)

import Data.Vector.Mutable (IOVector(..))
import Data.Vector.Mutable (unsafeNew)
import Data.Vector.Mutable (read)
import Data.Vector.Mutable (write)
import Data.Vector.Mutable (clone)
import Data.Vector (Vector(..))
import Data.Vector (fromList)
import Data.Vector (indexM)
import System.Random.MWC (GenIO(..))
import System.Random.MWC (createSystemRandom)
import System.Random.MWC (uniformR)
import System.Clock (getTime)
import System.Clock (diffTimeSpec)
import System.Clock (Clock(..))
import System.Clock (TimeSpec(..))
import GHC.Conc (numCapabilities)
import System.IO.Unsafe (unsafePerformIO)
import Prelude (quot)
import Prelude (rem)

import System.IO (putStrLn)

default (Int, Rat)

{-# INLINE div #-}
div :: _ => Int -> Int -> Int
div n d = (quot (I'.fromIntegral n) (I'.fromIntegral d))

{-# INLINE mod #-}
mod :: _ => Int -> Int -> Int
mod n d = (rem (I'.fromIntegral n) (I'.fromIntegral d))

{-# INLINE diff #-}
diff :: _ => TimeSpec -> TimeSpec -> TimeSpec
diff a b = (diffTimeSpec a b)

{-# INLINE toVector #-}
toVector :: forall a . _ => List a -> Vector a
toVector l = (fromList l)

num :: _ => Int
num = 1000

d :: _ => Int
d = 3

kinit :: _ => Int
kinit = ((d) * ((d) + 1))

workers :: _ => Int
workers = 2

packSize :: _ => Int
packSize = 10

isElem :: forall a . _ => a -> List a -> Bool
isElem l ls
  = case ls of
        [] -> False
        (l_ : ls_) -> ((l == l_) || (isElem l ls_))
{-# INLINE localIndex #-}
localIndex :: _ => Int -> Int
localIndex index
  = (((div
         (((div ((I'.fromIntegral index) - 1) (d)) + 1) - ((d) + 2))
         (workers))
        * (d))
       + (mod ((I'.fromIntegral index) - 1) (d)))

{-# INLINE actorIndex #-}
actorIndex :: _ => Int -> Int
actorIndex index
  = (mod (((div ((I'.fromIntegral index) - 1) (d)) + 1) - ((d) + 2))
       (workers))


class IWorker' a where  
        run_ :: Obj' a -> ABS' Unit   
        init_ :: List RObj -> Obj' a -> ABS' Unit
        request :: Int -> Obj' a -> ABS' Int
        requests :: List Int -> List Int -> Int -> Obj' a -> ABS' Unit
        delegates_ :: List Int -> List Int -> Obj' a -> ABS' Unit

data IWorker = forall a . IWorker' a => IWorker (Obj' a)

instance I'.Show IWorker where
        show _ = "IWorker"

instance I'.Eq IWorker where
        IWorker (Obj' ref1' _) == IWorker (Obj' ref2' _)
          = ref1' == I'.unsafeCoerce ref2'

instance IWorker' Null' where
        run_ = I'.undefined
        init_ = I'.undefined
        request = I'.undefined
        requests = I'.undefined
        delegates_ = I'.undefined

instance IWorker' a => Sub' (Obj' a) IWorker where
        up' = IWorker


data Worker = Worker{aliveDelegates'Worker :: Int,
                     arr'Worker :: IOVector (Fut Int), g'Worker :: GenIO,
                     initArr'Worker :: IOVector (Fut Int), size'Worker :: Int,
                     srcs'Worker :: IOVector (List Int),
                     tgts'Worker :: IOVector (List Int), thisTime'Worker :: Int,
                     workerId'Worker :: Int, ws2'Worker :: List RObj}

smart'Worker :: Int -> Int -> Worker
smart'Worker workerId'this size'this
  = (\ aliveDelegates'this ->
       (\ arr'this ->
          (\ initArr'this ->
             (\ ws2'this ->
                (\ srcs'this ->
                   (\ tgts'this ->
                      (\ thisTime'this ->
                         (\ g'this ->
                            (Worker (I'.fromIntegral aliveDelegates'this) arr'this g'this
                               initArr'this
                               (I'.fromIntegral size'this)
                               srcs'this
                               tgts'this
                               (I'.fromIntegral thisTime'this)
                               (I'.fromIntegral workerId'this)
                               ws2'this))
                           (I'.undefined :: GenIO))
                        (0 :: Int))
                     (I'.undefined :: IOVector (List Int)))
                  (I'.undefined :: IOVector (List Int)))
               ([] :: List RObj))
            (I'.undefined :: IOVector (Fut Int)))
         (I'.undefined :: IOVector (Fut Int)))
      (0 :: Int)

init'Worker :: Obj' Worker -> I'.IO ()

init'Worker this@(Obj' this' _)
  = do I'.writeIORef this' =<<
         ((\ this'' ->
             (\ v' -> this''{g'Worker = v'}) <$!> createSystemRandom)
            =<< I'.readIORef this')

instance IWorker' Worker where
        run_ this@(Obj' this' _)
          = do j :: IORef' Int <- I'.liftIO (I'.newIORef 0)
               i :: IORef' Int <- I'.liftIO
                                    ((\ this'' ->
                                        I'.newIORef
                                          (((d) + 2) +
                                             ((I'.fromIntegral (workerId'Worker this'')) - 1)))
                                       =<< I'.readIORef this')
               temp :: IORef' Int <- I'.liftIO
                                       ((\ this'' ->
                                           I'.newIORef
                                             ((kinit) +
                                                (((I'.fromIntegral (workerId'Worker this'')) - 1) *
                                                   d)))
                                          =<< I'.readIORef this')
               source :: IORef' Int <- I'.liftIO (I'.newIORef 0)
               target :: IORef' Int <- I'.liftIO (I'.newIORef 0)
               u :: IORef' Int <- I'.liftIO (I'.newIORef 0)
               fd :: IORef' (Fut Unit) <- I'.liftIO (I'.newIORef nullFuture')
               t :: IORef' Int <- I'.liftIO (I'.newIORef 0)
               maybeElement :: IORef' (Maybe Int) <- I'.liftIO (I'.newIORef Nothing)
               while
                 ((<) <$!> (I'.fromIntegral <$!> I'.readIORef t) <*>
                    (I'.pure workers))
                 (do _ <- I'.liftIO
                            ((\ this'' ->
                                (I'.join
                                   ((((I'.pure write <*> I'.pure (srcs'Worker this'')) <*>
                                        (I'.fromIntegral <$!> I'.readIORef t))
                                       <*> I'.pure []))))
                               =<< I'.readIORef this')
                     _ <- I'.liftIO
                            ((\ this'' ->
                                (I'.join
                                   ((((I'.pure write <*> I'.pure (tgts'Worker this'')) <*>
                                        (I'.fromIntegral <$!> I'.readIORef t))
                                       <*> I'.pure []))))
                               =<< I'.readIORef this')
                     I'.liftIO
                       (I'.writeIORef t =<<
                          ((+) <$!> (I'.fromIntegral <$!> I'.readIORef t) <*> I'.pure 1)))
               while
                 ((<=) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*> (I'.pure num))
                 (do I'.liftIO (I'.writeIORef j 1)
                     pastDraws :: IORef' (List Int) <- I'.liftIO (I'.newIORef [])
                     while
                       ((<=) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*> (I'.pure d))
                       (do I'.liftIO
                             (I'.writeIORef source =<<
                                (\ this'' ->
                                   (I'.join
                                      (((I'.pure uniformR <*>
                                           ((,) <$!> I'.pure 1 <*>
                                              ((*) <$!> (I'.fromIntegral <$!> I'.readIORef temp) <*>
                                                 I'.pure 2)))
                                          <*> I'.pure (g'Worker this'')))))
                                  =<< I'.readIORef this')
                           I'.liftIO
                             (I'.writeIORef target =<<
                                ((+) <$!> (I'.fromIntegral <$!> I'.readIORef temp) <*>
                                   (I'.fromIntegral <$!> I'.readIORef j)))
                           I'.liftIO (I'.writeIORef u 0)
                           if' <- I'.liftIO
                                    (((>) <$!> (I'.fromIntegral <$!> I'.readIORef source) <*>
                                        (I'.fromIntegral <$!> I'.readIORef temp)))
                           if if' then
                             do I'.liftIO
                                  (I'.writeIORef source =<<
                                     ((-) <$!> (I'.fromIntegral <$!> I'.readIORef source) <*>
                                        (I'.fromIntegral <$!> I'.readIORef temp)))
                                if' <- I'.liftIO
                                         (((>) <$!> (I'.fromIntegral <$!> I'.readIORef source) <*>
                                             (I'.pure kinit)))
                                if if' then
                                  do I'.liftIO
                                       (I'.writeIORef u =<<
                                          ((+) <$!>
                                             (I'.pure div <*>
                                                ((-) <$!> (I'.fromIntegral <$!> I'.readIORef source)
                                                   <*> I'.pure 1)
                                                <*> (I'.pure d))
                                             <*> I'.pure 1))
                                     if' <- I'.liftIO
                                              ((I'.pure isElem <*>
                                                  (I'.fromIntegral <$!> I'.readIORef u)
                                                  <*> I'.readIORef pastDraws))
                                     if if' then
                                       do I'.liftIO
                                            (I'.writeIORef j =<<
                                               ((-) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*>
                                                  I'.pure 1))
                                       else
                                       do I'.liftIO
                                            (I'.writeIORef pastDraws =<<
                                               ((:) <$!> (I'.fromIntegral <$!> I'.readIORef u) <*>
                                                  I'.readIORef pastDraws))
                                          I'.liftIO
                                            ((\ this'' ->
                                                (\ e1' ->
                                                   pro_give e1' =<<
                                                     (I'.fromIntegral <$!> I'.readIORef u))
                                                  =<<
                                                  (I'.join
                                                     (((I'.pure read <*>
                                                          I'.pure (arr'Worker this''))
                                                         <*>
                                                         (I'.pure localIndex <*>
                                                            (I'.fromIntegral <$!>
                                                               I'.readIORef target))))))
                                               =<< I'.readIORef this')
                                  else
                                  do I'.liftIO
                                       (I'.writeIORef u =<<
                                          (get =<<
                                             (\ this'' ->
                                                (I'.join
                                                   (((I'.pure read <*>
                                                        I'.pure (initArr'Worker this''))
                                                       <*>
                                                       (I'.fromIntegral <$!>
                                                          I'.readIORef source)))))
                                               =<< I'.readIORef this'))
                                     if' <- I'.liftIO
                                              (((==) <$!> (I'.fromIntegral <$!> I'.readIORef u) <*>
                                                  (I'.negate <$!> I'.pure 1)))
                                     if if' then
                                       do I'.liftIO
                                            (I'.writeIORef j =<<
                                               ((-) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*>
                                                  I'.pure 1))
                                       else
                                       do I'.liftIO
                                            (I'.writeIORef u =<<
                                               ((+) <$!>
                                                  (I'.pure div <*>
                                                     ((-) <$!>
                                                        (I'.fromIntegral <$!> I'.readIORef source)
                                                        <*> I'.pure 1)
                                                     <*> (I'.pure d))
                                                  <*> I'.pure 1))
                                          if' <- I'.liftIO
                                                   ((I'.pure isElem <*>
                                                       (I'.fromIntegral <$!> I'.readIORef u)
                                                       <*> I'.readIORef pastDraws))
                                          if if' then
                                            do I'.liftIO
                                                 (I'.writeIORef j =<<
                                                    ((-) <$!> (I'.fromIntegral <$!> I'.readIORef j)
                                                       <*> I'.pure 1))
                                            else
                                            do I'.liftIO
                                                 (I'.writeIORef pastDraws =<<
                                                    ((:) <$!> (I'.fromIntegral <$!> I'.readIORef u)
                                                       <*> I'.readIORef pastDraws))
                                               I'.liftIO
                                                 ((\ this'' ->
                                                     (\ e1' ->
                                                        pro_give e1' =<<
                                                          (I'.fromIntegral <$!> I'.readIORef u))
                                                       =<<
                                                       (I'.join
                                                          (((I'.pure read <*>
                                                               I'.pure (arr'Worker this''))
                                                              <*>
                                                              (I'.pure localIndex <*>
                                                                 (I'.fromIntegral <$!>
                                                                    I'.readIORef target))))))
                                                    =<< I'.readIORef this')
                             else
                             do if' <- I'.liftIO
                                         (((>) <$!> (I'.fromIntegral <$!> I'.readIORef source) <*>
                                             (I'.pure kinit)))
                                if if' then
                                  do aIndex :: IORef' Int <- I'.liftIO
                                                               (I'.newIORef =<<
                                                                  (I'.pure actorIndex <*>
                                                                     (I'.fromIntegral <$!>
                                                                        I'.readIORef source)))
                                     if' <- I'.liftIO
                                              ((\ this'' ->
                                                  ((==) <$!>
                                                     (I'.fromIntegral <$!> I'.readIORef aIndex)
                                                     <*>
                                                     ((-) <$!>
                                                        I'.pure
                                                          (I'.fromIntegral (workerId'Worker this''))
                                                        <*> I'.pure 1)))
                                                 =<< I'.readIORef this')
                                     if if' then
                                       do f :: IORef' (Fut Int) <- I'.liftIO
                                                                     (I'.newIORef =<<
                                                                        (\ this'' ->
                                                                           (I'.join
                                                                              (((I'.pure read <*>
                                                                                   I'.pure
                                                                                     (arr'Worker
                                                                                        this''))
                                                                                  <*>
                                                                                  (I'.pure
                                                                                     localIndex
                                                                                     <*>
                                                                                     (I'.fromIntegral
                                                                                        <$!>
                                                                                        I'.readIORef
                                                                                          source))))))
                                                                          =<< I'.readIORef this')
                                          I'.liftIO
                                            (I'.writeIORef maybeElement =<<
                                               (pro_try =<< I'.readIORef f))
                                          case' <- I'.liftIO (I'.readIORef maybeElement)
                                          case case' of
                                              Just v -> do if' <- I'.liftIO
                                                                    ((I'.pure isElem <*> I'.pure v
                                                                        <*> I'.readIORef pastDraws))
                                                           if if' then
                                                             do I'.liftIO
                                                                  (I'.writeIORef j =<<
                                                                     ((-) <$!>
                                                                        (I'.fromIntegral <$!>
                                                                           I'.readIORef j)
                                                                        <*> I'.pure 1))
                                                             else
                                                             do I'.liftIO
                                                                  (I'.writeIORef pastDraws =<<
                                                                     ((:) <$!> I'.pure v <*>
                                                                        I'.readIORef pastDraws))
                                                                I'.liftIO
                                                                  ((\ this'' ->
                                                                      (\ e1' ->
                                                                         pro_give e1' =<< I'.pure v)
                                                                        =<<
                                                                        (I'.join
                                                                           (((I'.pure read <*>
                                                                                I'.pure
                                                                                  (arr'Worker
                                                                                     this''))
                                                                               <*>
                                                                               (I'.pure localIndex
                                                                                  <*>
                                                                                  (I'.fromIntegral
                                                                                     <$!>
                                                                                     I'.readIORef
                                                                                       target))))))
                                                                     =<< I'.readIORef this')
                                              _ -> do tgt :: IORef' (List Int) <- I'.liftIO
                                                                                    (I'.newIORef =<<
                                                                                       (\ this'' ->
                                                                                          (I'.join
                                                                                             (((I'.pure
                                                                                                  read
                                                                                                  <*>
                                                                                                  I'.pure
                                                                                                    (tgts'Worker
                                                                                                       this''))
                                                                                                 <*>
                                                                                                 (I'.fromIntegral
                                                                                                    <$!>
                                                                                                    I'.readIORef
                                                                                                      aIndex)))))
                                                                                         =<<
                                                                                         I'.readIORef
                                                                                           this')
                                                      src :: IORef' (List Int) <- I'.liftIO
                                                                                    (I'.newIORef =<<
                                                                                       (\ this'' ->
                                                                                          (I'.join
                                                                                             (((I'.pure
                                                                                                  read
                                                                                                  <*>
                                                                                                  I'.pure
                                                                                                    (srcs'Worker
                                                                                                       this''))
                                                                                                 <*>
                                                                                                 (I'.fromIntegral
                                                                                                    <$!>
                                                                                                    I'.readIORef
                                                                                                      aIndex)))))
                                                                                         =<<
                                                                                         I'.readIORef
                                                                                           this')
                                                      _ <- I'.liftIO
                                                             ((\ this'' ->
                                                                 (I'.join
                                                                    ((((I'.pure write <*>
                                                                          I'.pure
                                                                            (tgts'Worker this''))
                                                                         <*>
                                                                         (I'.fromIntegral <$!>
                                                                            I'.readIORef aIndex))
                                                                        <*>
                                                                        ((:) <$!>
                                                                           (I'.fromIntegral <$!>
                                                                              I'.readIORef target)
                                                                           <*> I'.readIORef tgt)))))
                                                                =<< I'.readIORef this')
                                                      _ <- I'.liftIO
                                                             ((\ this'' ->
                                                                 (I'.join
                                                                    ((((I'.pure write <*>
                                                                          I'.pure
                                                                            (srcs'Worker this''))
                                                                         <*>
                                                                         (I'.fromIntegral <$!>
                                                                            I'.readIORef aIndex))
                                                                        <*>
                                                                        ((:) <$!>
                                                                           (I'.fromIntegral <$!>
                                                                              I'.readIORef source)
                                                                           <*> I'.readIORef src)))))
                                                                =<< I'.readIORef this')
                                                      I'.liftIO
                                                        (I'.writeIORef this' =<<
                                                           ((\ this'' ->
                                                               this''{aliveDelegates'Worker =
                                                                        ((I'.fromIntegral
                                                                            (aliveDelegates'Worker
                                                                               this''))
                                                                           + 1)})
                                                              <$!> I'.readIORef this'))
                                                      I'.liftIO
                                                        (I'.writeIORef this' =<<
                                                           ((\ this'' ->
                                                               this''{thisTime'Worker =
                                                                        ((I'.fromIntegral
                                                                            (thisTime'Worker
                                                                               this''))
                                                                           + 1)})
                                                              <$!> I'.readIORef this'))
                                       else
                                       do tgt :: IORef' (List Int) <- I'.liftIO
                                                                        (I'.newIORef =<<
                                                                           (\ this'' ->
                                                                              (I'.join
                                                                                 (((I'.pure read <*>
                                                                                      I'.pure
                                                                                        (tgts'Worker
                                                                                           this''))
                                                                                     <*>
                                                                                     (I'.fromIntegral
                                                                                        <$!>
                                                                                        I'.readIORef
                                                                                          aIndex)))))
                                                                             =<< I'.readIORef this')
                                          src :: IORef' (List Int) <- I'.liftIO
                                                                        (I'.newIORef =<<
                                                                           (\ this'' ->
                                                                              (I'.join
                                                                                 (((I'.pure read <*>
                                                                                      I'.pure
                                                                                        (srcs'Worker
                                                                                           this''))
                                                                                     <*>
                                                                                     (I'.fromIntegral
                                                                                        <$!>
                                                                                        I'.readIORef
                                                                                          aIndex)))))
                                                                             =<< I'.readIORef this')
                                          _ <- I'.liftIO
                                                 ((\ this'' ->
                                                     (I'.join
                                                        ((((I'.pure write <*>
                                                              I'.pure (tgts'Worker this''))
                                                             <*>
                                                             (I'.fromIntegral <$!>
                                                                I'.readIORef aIndex))
                                                            <*>
                                                            ((:) <$!>
                                                               (I'.fromIntegral <$!>
                                                                  I'.readIORef target)
                                                               <*> I'.readIORef tgt)))))
                                                    =<< I'.readIORef this')
                                          _ <- I'.liftIO
                                                 ((\ this'' ->
                                                     (I'.join
                                                        ((((I'.pure write <*>
                                                              I'.pure (srcs'Worker this''))
                                                             <*>
                                                             (I'.fromIntegral <$!>
                                                                I'.readIORef aIndex))
                                                            <*>
                                                            ((:) <$!>
                                                               (I'.fromIntegral <$!>
                                                                  I'.readIORef source)
                                                               <*> I'.readIORef src)))))
                                                    =<< I'.readIORef this')
                                          I'.liftIO
                                            (I'.writeIORef this' =<<
                                               ((\ this'' ->
                                                   this''{aliveDelegates'Worker =
                                                            ((I'.fromIntegral
                                                                (aliveDelegates'Worker this''))
                                                               + 1)})
                                                  <$!> I'.readIORef this'))
                                          I'.liftIO
                                            (I'.writeIORef this' =<<
                                               ((\ this'' ->
                                                   this''{thisTime'Worker =
                                                            ((I'.fromIntegral
                                                                (thisTime'Worker this''))
                                                               + 1)})
                                                  <$!> I'.readIORef this'))
                                  else
                                  do I'.liftIO
                                       (I'.writeIORef u =<<
                                          (get =<<
                                             (\ this'' ->
                                                (I'.join
                                                   (((I'.pure read <*>
                                                        I'.pure (initArr'Worker this''))
                                                       <*>
                                                       (I'.fromIntegral <$!>
                                                          I'.readIORef source)))))
                                               =<< I'.readIORef this'))
                                     if' <- I'.liftIO
                                              (((==) <$!> (I'.fromIntegral <$!> I'.readIORef u) <*>
                                                  (I'.negate <$!> I'.pure 1)))
                                     if if' then
                                       do I'.liftIO
                                            (I'.writeIORef j =<<
                                               ((-) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*>
                                                  I'.pure 1))
                                       else
                                       do if' <- I'.liftIO
                                                   ((I'.pure isElem <*>
                                                       (I'.fromIntegral <$!> I'.readIORef u)
                                                       <*> I'.readIORef pastDraws))
                                          if if' then
                                            do I'.liftIO
                                                 (I'.writeIORef j =<<
                                                    ((-) <$!> (I'.fromIntegral <$!> I'.readIORef j)
                                                       <*> I'.pure 1))
                                            else
                                            do I'.liftIO
                                                 (I'.writeIORef pastDraws =<<
                                                    ((:) <$!> (I'.fromIntegral <$!> I'.readIORef u)
                                                       <*> I'.readIORef pastDraws))
                                               I'.liftIO
                                                 ((\ this'' ->
                                                     (\ e1' ->
                                                        pro_give e1' =<<
                                                          (I'.fromIntegral <$!> I'.readIORef u))
                                                       =<<
                                                       (I'.join
                                                          (((I'.pure read <*>
                                                               I'.pure (arr'Worker this''))
                                                              <*>
                                                              (I'.pure localIndex <*>
                                                                 (I'.fromIntegral <$!>
                                                                    I'.readIORef target))))))
                                                    =<< I'.readIORef this')
                           I'.liftIO
                             (I'.writeIORef j =<<
                                ((+) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*> I'.pure 1)))
                     I'.liftIO
                       (I'.writeIORef i =<<
                          ((+) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*>
                             (I'.pure workers)))
                     I'.liftIO
                       (I'.writeIORef temp =<<
                          ((+) <$!> (I'.fromIntegral <$!> I'.readIORef temp) <*>
                             ((*) <$!> (I'.pure d) <*> (I'.pure workers))))
                     (\ this'' ->
                        I'.when ((I'.fromIntegral (thisTime'Worker this'')) >= (packSize))
                          (do iw :: IORef' Int <- I'.liftIO (I'.newIORef 0)
                              delInx :: IORef' Int <- I'.liftIO (I'.newIORef 0)
                              while
                                ((<) <$!> (I'.fromIntegral <$!> I'.readIORef iw) <*>
                                   (I'.pure workers))
                                (do tmp :: IORef' (List Int) <- I'.liftIO
                                                                  (I'.newIORef =<<
                                                                     (\ this'' ->
                                                                        (I'.join
                                                                           (((I'.pure read <*>
                                                                                I'.pure
                                                                                  (srcs'Worker
                                                                                     this''))
                                                                               <*>
                                                                               (I'.fromIntegral <$!>
                                                                                  I'.readIORef
                                                                                    iw)))))
                                                                       =<< I'.readIORef this')
                                    w :: IORef' RObj <- I'.liftIO
                                                             (I'.newIORef =<<
                                                                (\ this'' ->
                                                                   (I'.pure nth <*>
                                                                      I'.pure (ws2'Worker this'')
                                                                      <*>
                                                                      (I'.fromIntegral <$!>
                                                                         I'.readIORef iw)))
                                                                  =<< I'.readIORef this')
                                    when' <- I'.liftIO
                                               (((not) <$!>
                                                   ((==) <$!> I'.readIORef tmp <*> I'.pure [])))
                                    I'.when when'
                                      (do 
                                          _ <- I'.lift
                                                 (I'.join ((\ this'' ->
                                                            I'.pure requests_i <*>
                                                            (I'.pure reverse <*> I'.liftIO (I'.readIORef tmp))
                                                            <*>
                                                            (I'.pure reverse <*>
                                                               (I'.liftIO (I'.join
                                                                  (((I'.pure read <*>
                                                                       I'.pure (tgts'Worker this''))
                                                                      <*>
                                                                      (I'.fromIntegral <$!>
                                                                         I'.liftIO (I'.readIORef iw)))))))
                                                            <*>
                                                            ((-) <$!>
                                                               I'.pure
                                                                 (I'.fromIntegral
                                                                    (workerId'Worker this''))
                                                               <*> I'.pure 1)
                                                            <*> I'.liftIO (I'.readIORef w))
                                                    =<< I'.liftIO (I'.readIORef this'))) :: ABS' ()

                                          -- _ <- I'.liftIO
                                          --        ((\ this'' ->
                                          --            (\ (IWorker obj') ->
                                          --               (obj' <!!>) =<<
                                          --                 I'.pure requests <*>
                                          --                   (I'.pure reverse <*> I'.readIORef tmp)
                                          --                   <*>
                                          --                   (I'.pure reverse <*>
                                          --                      (I'.join
                                          --                         (((I'.pure read <*>
                                          --                              I'.pure (tgts'Worker this''))
                                          --                             <*>
                                          --                             (I'.fromIntegral <$!>
                                          --                                I'.readIORef iw)))))
                                          --                   <*>
                                          --                   ((-) <$!>
                                          --                      I'.pure
                                          --                        (I'.fromIntegral
                                          --                           (workerId'Worker this''))
                                          --                      <*> I'.pure 1))
                                          --              =<< I'.readIORef w)
                                          --           =<< I'.readIORef this')
                                          I'.pure ())
                                    I'.liftIO
                                      (I'.writeIORef iw =<<
                                         ((+) <$!> (I'.fromIntegral <$!> I'.readIORef iw) <*>
                                            I'.pure 1))
                                    suspend this)
                              I'.liftIO
                                (I'.writeIORef this' =<<
                                   ((\ this'' -> this''{thisTime'Worker = 0}) <$!>
                                      I'.readIORef this'))
                              I'.liftIO (I'.writeIORef t 0)
                              while
                                ((<) <$!> (I'.fromIntegral <$!> I'.readIORef t) <*>
                                   (I'.pure workers))
                                (do _ <- I'.liftIO
                                           ((\ this'' ->
                                               (I'.join
                                                  ((((I'.pure write <*>
                                                        I'.pure (srcs'Worker this''))
                                                       <*> (I'.fromIntegral <$!> I'.readIORef t))
                                                      <*> I'.pure []))))
                                              =<< I'.readIORef this')
                                    _ <- I'.liftIO
                                           ((\ this'' ->
                                               (I'.join
                                                  ((((I'.pure write <*>
                                                        I'.pure (tgts'Worker this''))
                                                       <*> (I'.fromIntegral <$!> I'.readIORef t))
                                                      <*> I'.pure []))))
                                              =<< I'.readIORef this')
                                    I'.liftIO
                                      (I'.writeIORef t =<<
                                         ((+) <$!> (I'.fromIntegral <$!> I'.readIORef t) <*>
                                            I'.pure 1)))))
                       =<< I'.liftIO (I'.readIORef this'))
               (\ this'' ->
                  I'.when ((I'.fromIntegral (thisTime'Worker this'')) > 0)
                    (do iw :: IORef' Int <- I'.liftIO (I'.newIORef 0)
                        delInx :: IORef' Int <- I'.liftIO (I'.newIORef 0)
                        while
                          ((<) <$!> (I'.fromIntegral <$!> I'.readIORef iw) <*>
                             (I'.pure workers))
                          (do tmp :: IORef' (List Int) <- I'.liftIO
                                                            (I'.newIORef =<<
                                                               (\ this'' ->
                                                                  (I'.join
                                                                     (((I'.pure read <*>
                                                                          I'.pure
                                                                            (srcs'Worker this''))
                                                                         <*>
                                                                         (I'.fromIntegral <$!>
                                                                            I'.readIORef iw)))))
                                                                 =<< I'.readIORef this')
                              w :: IORef' RObj <- I'.liftIO
                                                       (I'.newIORef =<<
                                                          (\ this'' ->
                                                             (I'.pure nth <*>
                                                                I'.pure (ws2'Worker this'')
                                                                <*>
                                                                (I'.fromIntegral <$!>
                                                                   I'.readIORef iw)))
                                                            =<< I'.readIORef this')
                              when' <- I'.liftIO
                                         (((not) <$!> ((==) <$!> I'.readIORef tmp <*> I'.pure [])))
                              I'.when when'
                                (do 
                                    _ <- I'.lift
                                                 (I'.join ((\ this'' ->
                                                            I'.pure requests_i <*>
                                                            (I'.pure reverse <*> I'.liftIO (I'.readIORef tmp))
                                                            <*>
                                                            (I'.pure reverse <*>
                                                               (I'.liftIO (I'.join
                                                                  (((I'.pure read <*>
                                                                       I'.pure (tgts'Worker this''))
                                                                      <*>
                                                                      (I'.fromIntegral <$!>
                                                                         I'.liftIO (I'.readIORef iw)))))))
                                                            <*>
                                                            ((-) <$!>
                                                               I'.pure
                                                                 (I'.fromIntegral
                                                                    (workerId'Worker this''))
                                                               <*> I'.pure 1)
                                                            <*> I'.liftIO (I'.readIORef w))
                                                    =<< I'.liftIO (I'.readIORef this'))) :: ABS' ()


                                    -- _ <- I'.liftIO
                                    --        ((\ this'' ->
                                    --            (\ (IWorker obj') ->
                                    --               (obj' <!!>) =<<
                                    --                 I'.pure requests <*>
                                    --                   (I'.pure reverse <*> I'.readIORef tmp)
                                    --                   <*>
                                    --                   (I'.pure reverse <*>
                                    --                      (I'.join
                                    --                         (((I'.pure read <*>
                                    --                              I'.pure (tgts'Worker this''))
                                    --                             <*>
                                    --                             (I'.fromIntegral <$!>
                                    --                                I'.readIORef iw)))))
                                    --                   <*>
                                    --                   ((-) <$!>
                                    --                      I'.pure
                                    --                        (I'.fromIntegral
                                    --                           (workerId'Worker this''))
                                    --                      <*> I'.pure 1))
                                    --              =<< I'.readIORef w)
                                    --           =<< I'.readIORef this')
                                    I'.pure ())
                              I'.liftIO
                                (I'.writeIORef iw =<<
                                   ((+) <$!> (I'.fromIntegral <$!> I'.readIORef iw) <*>
                                      I'.pure 1)))))
                 =<< I'.liftIO (I'.readIORef this')
               awaitBool' this
                 (\ this'' ->
                    ((I'.fromIntegral (aliveDelegates'Worker this'')) == 0))
        init_ ws this@(Obj' this' _)
          = do I'.liftIO
                 (I'.writeIORef this' =<<
                    ((\ this'' -> this''{ws2'Worker = ws}) <$!> I'.readIORef this'))
               I'.liftIO
                 (I'.writeIORef this' =<<
                    ((\ this'' ->
                        (\ v' -> this''{arr'Worker = v'}) <$!>
                          (I'.join
                             ((I'.pure unsafeNew <*>
                                 ((+) <$!> I'.pure (I'.fromIntegral (size'Worker this'')) <*>
                                    I'.pure 1)))))
                       =<< I'.readIORef this'))
               I'.liftIO
                 (I'.writeIORef this' =<<
                    ((\ this'' ->
                        (\ v' -> this''{initArr'Worker = v'}) <$!>
                          (I'.join
                             ((I'.pure unsafeNew <*>
                                 ((+) <$!> (I'.pure kinit) <*> I'.pure 1)))))
                       =<< I'.readIORef this'))
               I'.liftIO
                 (I'.writeIORef this' =<<
                    ((\ this'' ->
                        (\ v' -> this''{srcs'Worker = v'}) <$!>
                          (I'.join
                             ((I'.pure unsafeNew <*>
                                 ((+) <$!> (I'.pure workers) <*> I'.pure 0)))))
                       =<< I'.readIORef this'))
               I'.liftIO
                 (I'.writeIORef this' =<<
                    ((\ this'' ->
                        (\ v' -> this''{tgts'Worker = v'}) <$!>
                          (I'.join
                             ((I'.pure unsafeNew <*>
                                 ((+) <$!> (I'.pure workers) <*> I'.pure 0)))))
                       =<< I'.readIORef this'))
               c :: IORef' (Fut Int) <- I'.liftIO (I'.newIORef nullFuture')
               index :: IORef' Int <- I'.liftIO (I'.newIORef 1)
               i :: IORef' Int <- I'.liftIO (I'.newIORef 0)
               j :: IORef' Int <- I'.liftIO (I'.newIORef 0)
               while
                 ((<=) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*> (I'.pure d))
                 (do I'.liftIO (I'.writeIORef j 1)
                     while
                       ((<=) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*> (I'.pure d))
                       (do I'.liftIO (I'.writeIORef c =<< pro_new)
                           I'.liftIO
                             (I'.writeIORef index =<<
                                ((+) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*>
                                   ((*) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*>
                                      (I'.pure d))))
                           if' <- I'.liftIO
                                    (((<=) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*>
                                        (I'.fromIntegral <$!> I'.readIORef i)))
                           if if' then
                             do I'.liftIO
                                  ((\ e1' -> pro_give e1' =<< (I'.fromIntegral <$!> I'.readIORef j))
                                     =<< I'.readIORef c)
                             else
                             do I'.liftIO
                                  ((\ e1' -> pro_give e1' =<< (I'.negate <$!> I'.pure 1)) =<<
                                     I'.readIORef c)
                           _ <- I'.liftIO
                                  ((\ this'' ->
                                      (I'.join
                                         ((((I'.pure write <*> I'.pure (initArr'Worker this'')) <*>
                                              (I'.fromIntegral <$!> I'.readIORef index))
                                             <*> I'.readIORef c))))
                                     =<< I'.readIORef this')
                           I'.liftIO
                             (I'.writeIORef j =<<
                                ((+) <$!> (I'.fromIntegral <$!> I'.readIORef j) <*> I'.pure 1)))
                     I'.liftIO
                       (I'.writeIORef i =<<
                          ((+) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*> I'.pure 1)))
               I'.liftIO (I'.writeIORef index 0)
               while
                 ((\ this'' ->
                     ((<=) <$!> (I'.fromIntegral <$!> I'.readIORef index) <*>
                        I'.pure (I'.fromIntegral (size'Worker this''))))
                    =<< I'.readIORef this')
                 (do I'.liftIO (I'.writeIORef c =<< pro_new)
                     _ <- I'.liftIO
                            ((\ this'' ->
                                (I'.join
                                   ((((I'.pure write <*> I'.pure (arr'Worker this'')) <*>
                                        (I'.fromIntegral <$!> I'.readIORef index))
                                       <*> I'.readIORef c))))
                               =<< I'.readIORef this')
                     I'.liftIO
                       (I'.writeIORef index =<<
                          ((+) <$!> (I'.fromIntegral <$!> I'.readIORef index) <*>
                             I'.pure 1)))
        request source this@(Obj' this' _)
          = do n :: IORef' Int <- I'.liftIO (I'.newIORef 0)
               if ((I'.fromIntegral source) > (kinit)) then
                 do f :: IORef' (Fut Int) <- I'.liftIO
                                               (I'.newIORef =<<
                                                  (\ this'' ->
                                                     (I'.join
                                                        (((I'.pure read <*>
                                                             I'.pure (arr'Worker this''))
                                                            <*>
                                                            (I'.pure localIndex <*>
                                                               I'.pure (I'.fromIntegral source))))))
                                                    =<< I'.readIORef this')
                    awaitFuture' this =<< I'.liftIO (I'.readIORef f)
                    I'.liftIO (I'.writeIORef n =<< (get =<< I'.readIORef f))
                 else
                 do I'.liftIO
                      (I'.writeIORef n =<<
                         (get =<<
                            (\ this'' ->
                               (I'.join
                                  (((I'.pure read <*> I'.pure (initArr'Worker this'')) <*>
                                      I'.pure (I'.fromIntegral source)))))
                              =<< I'.readIORef this'))
               I'.liftIO ((I'.fromIntegral <$!> I'.readIORef n))
        requests src tgt aIn this@(Obj' this' _)
          = do I'.liftIO (println "inside requests call")
               srcd :: IORef' (List Int) <- I'.liftIO (I'.newIORef [])
               src2 :: IORef' (List Int) <- I'.liftIO (I'.newIORef src)
               tgtd :: IORef' (List Int) <- I'.liftIO (I'.newIORef [])
               tgt2 :: IORef' (List Int) <- I'.liftIO (I'.newIORef tgt)
               f2 :: IORef' (Fut Unit) <- I'.liftIO (I'.newIORef nullFuture')
               while ((not) <$!> ((==) <$!> I'.readIORef src2 <*> I'.pure []))
                 (do source :: IORef' Int <- I'.liftIO
                                               (I'.newIORef =<<
                                                  (I'.pure head <*> I'.readIORef src2))
                     I'.liftIO
                       (I'.writeIORef src2 =<< (I'.pure tail <*> I'.readIORef src2))
                     target :: IORef' Int <- I'.liftIO
                                               (I'.newIORef =<<
                                                  (I'.pure head <*> I'.readIORef tgt2))
                     I'.liftIO
                       (I'.writeIORef tgt2 =<< (I'.pure tail <*> I'.readIORef tgt2))
                     t :: IORef' Int <- I'.liftIO (I'.newIORef 0)
                     if' <- I'.liftIO
                              (((>) <$!> (I'.fromIntegral <$!> I'.readIORef source) <*>
                                  (I'.pure kinit)))
                     if if' then
                       do f :: IORef' (Fut Int) <- I'.liftIO
                                                     (I'.newIORef =<<
                                                        (\ this'' ->
                                                           (I'.join
                                                              (((I'.pure read <*>
                                                                   I'.pure (arr'Worker this''))
                                                                  <*>
                                                                  (I'.pure localIndex <*>
                                                                     (I'.fromIntegral <$!>
                                                                        I'.readIORef source))))))
                                                          =<< I'.readIORef this')
                          maybeElement :: IORef' (Maybe Int) <- I'.liftIO
                                                                  (I'.newIORef =<<
                                                                     (pro_try =<< I'.readIORef f))
                          if' <- I'.liftIO ((I'.pure isJust <*> I'.readIORef maybeElement))
                          if if' then
                            do I'.liftIO
                                 (I'.writeIORef t =<<
                                    (I'.pure fromJust <*> I'.readIORef maybeElement))
                            else
                            do if' <- I'.liftIO
                                        (((not) <$!> ((==) <$!> I'.readIORef srcd <*> I'.pure [])))
                               if if' then
                                 do iw :: IORef' RObj <- I'.liftIO
                                                              ((\ this'' ->
                                                                  I'.newIORef
                                                                    (nth (ws2'Worker this'')
                                                                       (I'.fromIntegral aIn)))
                                                                 =<< I'.readIORef this')

                                    _ <- I'.lift (I'.join (
                                                   I'.pure delegates__i <*>
                                                   (I'.pure reverse <*> I'.liftIO (I'.readIORef srcd))
                                                   <*> (I'.pure reverse <*> I'.liftIO (I'.readIORef tgtd))
                                                   <*> I'.liftIO (I'.readIORef iw)
                                                  )) :: ABS' ()

                                    -- _ <- I'.liftIO
                                    --        ((\ (IWorker obj') ->
                                    --            (obj' <!!>) =<<
                                    --              I'.pure delegates_ <*>
                                    --                (I'.pure reverse <*> I'.readIORef srcd)
                                    --                <*> (I'.pure reverse <*> I'.readIORef tgtd))
                                    --           =<< I'.readIORef iw)
                                    I'.liftIO (I'.writeIORef srcd [])
                                    I'.liftIO (I'.writeIORef tgtd [])
                                    awaitFuture' this =<< I'.liftIO (I'.readIORef f)
                                    I'.liftIO (I'.writeIORef t =<< (get =<< I'.readIORef f))
                                 else
                                 do awaitFuture' this =<< I'.liftIO (I'.readIORef f)
                                    I'.liftIO (I'.writeIORef t =<< (get =<< I'.readIORef f))
                       else
                       do I'.liftIO
                            (I'.writeIORef t =<<
                               (get =<<
                                  (\ this'' ->
                                     (I'.join
                                        (((I'.pure read <*> I'.pure (initArr'Worker this'')) <*>
                                            (I'.fromIntegral <$!> I'.readIORef source)))))
                                    =<< I'.readIORef this'))
                     I'.liftIO
                       (I'.writeIORef srcd =<<
                          ((:) <$!> (I'.fromIntegral <$!> I'.readIORef t) <*>
                             I'.readIORef srcd))
                     I'.liftIO
                       (I'.writeIORef tgtd =<<
                          ((:) <$!> (I'.fromIntegral <$!> I'.readIORef target) <*>
                             I'.readIORef tgtd)))
               I'.liftIO (println "after while of requests")
               when' <- I'.liftIO
                          (((not) <$!> ((==) <$!> I'.readIORef srcd <*> I'.pure [])))
               I'.when when'
                 (do iw :: IORef' RObj <- I'.liftIO
                                               ((\ this'' ->
                                                   I'.newIORef
                                                     (nth (ws2'Worker this'')
                                                        (I'.fromIntegral aIn)))
                                                  =<< I'.readIORef this')
                     _ <- I'.lift ( I'.join (
                                                   I'.pure delegates__i <*>
                                                   (I'.pure reverse <*> I'.liftIO (I'.readIORef srcd))
                                                   <*> (I'.pure reverse <*> I'.liftIO (I'.readIORef tgtd))
                                                   <*> I'.liftIO (I'.readIORef iw)
                                                  )) :: ABS' ()

                     -- _ <- I'.liftIO
                     --        ((\ (IWorker obj') ->
                     --            (obj' <!!>) =<<
                     --              I'.pure delegates_ <*> (I'.pure reverse <*> I'.readIORef srcd) <*>
                     --                (I'.pure reverse <*> I'.readIORef tgtd))
                     --           =<< I'.readIORef iw)
                     I'.pure ())
        delegates_ src2 tgt2 this@(Obj' this' _)
          = do src :: IORef' (List Int) <- I'.liftIO (I'.newIORef src2)
               tgt :: IORef' (List Int) <- I'.liftIO (I'.newIORef tgt2)
               while ((not) <$!> ((==) <$!> I'.readIORef src <*> I'.pure []))
                 (do u :: IORef' Int <- I'.liftIO
                                          (I'.newIORef =<< (I'.pure head <*> I'.readIORef src))
                     target :: IORef' Int <- I'.liftIO
                                               (I'.newIORef =<< (I'.pure head <*> I'.readIORef tgt))
                     I'.liftIO (I'.writeIORef src =<< (I'.pure tail <*> I'.readIORef src))
                     I'.liftIO (I'.writeIORef tgt =<< (I'.pure tail <*> I'.readIORef tgt))
                     found :: IORef' Bool <- I'.liftIO (I'.newIORef False)
                     when' <- I'.liftIO
                                (((not) <$!>
                                    ((==) <$!> (I'.fromIntegral <$!> I'.readIORef u) <*>
                                       (I'.negate <$!> I'.pure 1))))
                     I'.when when'
                       (do i :: IORef' Int <- I'.liftIO
                                                (I'.newIORef =<<
                                                   ((+) <$!>
                                                      ((*) <$!>
                                                         (I'.pure div <*>
                                                            ((-) <$!>
                                                               (I'.fromIntegral <$!>
                                                                  I'.readIORef target)
                                                               <*> I'.pure 1)
                                                            <*> (I'.pure d))
                                                         <*> (I'.pure d))
                                                      <*> I'.pure 1))
                           lCurrentNode :: IORef' Int <- I'.liftIO
                                                           (I'.newIORef =<<
                                                              ((-) <$!>
                                                                 ((+) <$!>
                                                                    (I'.fromIntegral <$!>
                                                                       I'.readIORef i)
                                                                    <*> (I'.pure d))
                                                                 <*> I'.pure 1))
                           while
                             ((<=) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*>
                                (I'.fromIntegral <$!> I'.readIORef lCurrentNode))
                             (do maybeElement :: IORef' (Maybe Int) <- I'.liftIO
                                                                         (I'.newIORef Nothing)
                                 I'.liftIO
                                   (I'.writeIORef maybeElement =<<
                                      (pro_try =<<
                                         (\ this'' ->
                                            (I'.join
                                               (((I'.pure read <*> I'.pure (arr'Worker this'')) <*>
                                                   (I'.pure localIndex <*>
                                                      (I'.fromIntegral <$!> I'.readIORef i))))))
                                           =<< I'.readIORef this'))
                                 case' <- I'.liftIO (I'.readIORef maybeElement)
                                 case case' of
                                     Just v -> do when' <- I'.liftIO
                                                             (((==) <$!>
                                                                 (I'.fromIntegral <$!>
                                                                    I'.readIORef u)
                                                                 <*> I'.pure v))
                                                  I'.when when'
                                                    (do I'.liftIO (I'.writeIORef found True)
                                                        I'.liftIO
                                                          (I'.writeIORef i =<<
                                                             ((+) <$!>
                                                                (I'.fromIntegral <$!>
                                                                   I'.readIORef lCurrentNode)
                                                                <*> I'.pure 1)))
                                     _ -> I'.pure ()
                                 I'.liftIO
                                   (I'.writeIORef i =<<
                                      ((+) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*>
                                         I'.pure 1))))
                     if' <- I'.liftIO
                              (((||) <$!> I'.readIORef found <*>
                                  ((==) <$!> (I'.fromIntegral <$!> I'.readIORef u) <*>
                                     (I'.negate <$!> I'.pure 1))))
                     if if' then
                       do I'.liftIO
                            (I'.writeIORef u =<<
                               ((*) <$!>
                                  (I'.pure div <*>
                                     ((-) <$!> (I'.fromIntegral <$!> I'.readIORef target) <*>
                                        I'.pure 1)
                                     <*> (I'.pure d))
                                  <*> (I'.pure d)))
                          u2 :: IORef' Int <- I'.liftIO
                                                (I'.newIORef =<<
                                                   (\ this'' ->
                                                      (I'.join
                                                         (((I'.pure uniformR <*>
                                                              ((,) <$!>
                                                                 ((+) <$!> (I'.pure kinit) <*>
                                                                    I'.pure 1)
                                                                 <*>
                                                                 (I'.fromIntegral <$!>
                                                                    I'.readIORef u)))
                                                             <*> I'.pure (g'Worker this'')))))
                                                     =<< I'.readIORef this')
                          w :: IORef' RObj <- I'.liftIO
                                                   (I'.newIORef =<<
                                                      (\ this'' ->
                                                         (I'.pure nth <*>
                                                            I'.pure (ws2'Worker this'')
                                                            <*>
                                                            (I'.pure actorIndex <*>
                                                               (I'.fromIntegral <$!>
                                                                  I'.readIORef u2))))
                                                        =<< I'.readIORef this')
                          fp :: IORef' RFut <- (I'.liftIO . I'.newIORef) =<<
                                                              (I'.liftIO (I'.readIORef u2) >>= \ u2' -> I'.liftIO (I'.readIORef w) >>= \ w' ->
                                                                    I'.lift (request_i this u2' w')
                                                                  )
                          -- fp :: IORef' (Fut Int) <- I'.liftIO
                          --                             (I'.newIORef =<<
                          --                                ((\ (IWorker obj') ->
                          --                                    (obj' <!>) =<<
                          --                                      I'.pure request <*>
                          --                                        (I'.fromIntegral <$!>
                          --                                           I'.readIORef u2))
                          --                                   =<< I'.readIORef w))
                          _ <- (this <..>) =<<
                                 I'.liftIO
                                   (I'.pure delegate''Worker <*> I'.readIORef fp <*>
                                      (I'.fromIntegral <$!> I'.readIORef target))
                          I'.pure ()
                       else
                       do I'.liftIO
                            ((\ this'' ->
                                (\ e1' -> pro_give e1' =<< (I'.fromIntegral <$!> I'.readIORef u))
                                  =<<
                                  (I'.join
                                     (((I'.pure read <*> I'.pure (arr'Worker this'')) <*>
                                         (I'.pure localIndex <*>
                                            (I'.fromIntegral <$!> I'.readIORef target))))))
                               =<< I'.readIORef this')
                          I'.liftIO
                            (I'.writeIORef this' =<<
                               ((\ this'' ->
                                   this''{aliveDelegates'Worker =
                                            ((I'.fromIntegral (aliveDelegates'Worker this'')) - 1)})
                                  <$!> I'.readIORef this')))




delegate''Worker :: RFut -> Int -> Obj' Worker -> ABS' Unit
delegate''Worker ft target this@(Obj' this' _)
  = do await_i this ft
       --awaitFuture' this ft
       --u :: IORef' Int <- I'.liftIO (I'.newIORef =<< get ft)
       u :: IORef' Int <- I'.lift ((I'.liftIO . I'.newIORef) =<< get_i this ft)
       found :: IORef' Bool <- I'.liftIO (I'.newIORef False)
       when' <- I'.liftIO
                  (((not) <$!>
                      ((==) <$!> (I'.fromIntegral <$!> I'.readIORef u) <*>
                         (I'.negate <$!> I'.pure 1))))
       I'.when when'
         (do i :: IORef' Int <- I'.liftIO
                                  (I'.newIORef
                                     (((div ((I'.fromIntegral target) - 1) (d)) * (d)) + 1))
             lCurrentNode :: IORef' Int <- I'.liftIO
                                             (I'.newIORef =<<
                                                ((-) <$!>
                                                   ((+) <$!> (I'.fromIntegral <$!> I'.readIORef i)
                                                      <*> (I'.pure d))
                                                   <*> I'.pure 1))
             maybeElement :: IORef' (Maybe Int) <- I'.liftIO(I'.newIORef Nothing)
             while
               ((<=) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*>
                  (I'.fromIntegral <$!> I'.readIORef lCurrentNode))
               (do 
                   I'.liftIO
                     (I'.writeIORef maybeElement =<<
                        (pro_try =<<
                           (\ this'' ->
                              (I'.join
                                 (((I'.pure read <*> I'.pure (arr'Worker this'')) <*>
                                     (I'.pure localIndex <*>
                                        (I'.fromIntegral <$!> I'.readIORef i))))))
                             =<< I'.readIORef this'))
                   case' <- I'.liftIO (I'.readIORef maybeElement)
                   case case' of
                       Just v -> do when' <- I'.liftIO
                                               (((==) <$!> (I'.fromIntegral <$!> I'.readIORef u) <*>
                                                   I'.pure v))
                                    I'.when when'
                                      (do I'.liftIO (I'.writeIORef found True)
                                          I'.liftIO
                                            (I'.writeIORef i =<<
                                               ((+) <$!>
                                                  (I'.fromIntegral <$!> I'.readIORef lCurrentNode)
                                                  <*> I'.pure 1)))
                       _ -> I'.pure ()
                   I'.liftIO
                     (I'.writeIORef i =<<
                        ((+) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*> I'.pure 1))))
       if' <- I'.liftIO
                (((||) <$!> I'.readIORef found <*>
                    ((==) <$!> (I'.fromIntegral <$!> I'.readIORef u) <*>
                       (I'.negate <$!> I'.pure 1))))
       if if' then
         do I'.liftIO
              (I'.writeIORef u ((div ((I'.fromIntegral target) - 1) (d)) * (d)))
            u2 :: IORef' Int <- I'.liftIO
                                  (I'.newIORef =<<
                                     (\ this'' ->
                                        (I'.join
                                           (((I'.pure uniformR <*>
                                                ((,) <$!> ((+) <$!> (I'.pure kinit) <*> I'.pure 1)
                                                   <*> (I'.fromIntegral <$!> I'.readIORef u)))
                                               <*> I'.pure (g'Worker this'')))))
                                       =<< I'.readIORef this')
            w :: IORef' RObj <- I'.liftIO
                                     (I'.newIORef =<<
                                        (\ this'' ->
                                           (I'.pure nth <*> I'.pure (ws2'Worker this'') <*>
                                              (I'.pure actorIndex <*>
                                                 (I'.fromIntegral <$!> I'.readIORef u2))))
                                          =<< I'.readIORef this')
            fp :: IORef' RFut <- (I'.liftIO . I'.newIORef) =<<
                                                              (I'.liftIO (I'.readIORef u2) >>= \ u2' -> I'.liftIO (I'.readIORef w) >>= \ w' ->
                                                                    I'.lift (request_i this u2' w')
                                                                  )
            -- fp :: IORef' (Fut Int) <- I'.liftIO
            --                             (I'.newIORef =<<
            --                                ((\ (IWorker obj') ->
            --                                    (obj' <!>) =<<
            --                                      I'.pure request <*>
            --                                        (I'.fromIntegral <$!> I'.readIORef u2))
            --                                   =<< I'.readIORef w))
            _ <- (this <..>) =<<
                   I'.liftIO
                     (I'.pure delegate''Worker <*> I'.readIORef fp <*>
                        I'.pure (I'.fromIntegral target))
            I'.pure ()
         else
         do I'.liftIO
              ((\ this'' ->
                  (\ e1' -> pro_give e1' =<< (I'.fromIntegral <$!> I'.readIORef u))
                    =<<
                    (I'.join
                       (((I'.pure read <*> I'.pure (arr'Worker this'')) <*>
                           (I'.pure localIndex <*> I'.pure (I'.fromIntegral target))))))
                 =<< I'.readIORef this')
            I'.liftIO
              (I'.writeIORef this' =<<
                 ((\ this'' ->
                     this''{aliveDelegates'Worker =
                              ((I'.fromIntegral (aliveDelegates'Worker this'')) - 1)})
                    <$!> I'.readIORef this'))



{-# INLINABLE (<!!>) #-}
-- | fire&forget async, unliftIOed
(<!!>) :: Obj' Worker -> (Obj' Worker -> ABS' b) -> I'.IO ()
(<!!>) obj@(Obj' _ otherCog@(Cog _ otherMailBox)) methodPartiallyApplied = 
  atomically $ writeTQueue otherMailBox (do
               -- we throw away the result (if we had "destiny" primitive then this optimization could not be easily applied
               (() <$ methodPartiallyApplied obj)
               back' obj)


{-# INLINABLE awaitFuture' #-}
awaitFuture' :: Obj' Worker -> Fut a -> ABS' ()
awaitFuture' obj@(Obj' _ thisCog@(Cog _ thisMailBox)) mvar = do
  empty <- I'.liftIO $ I'.isEmptyMVar mvar -- according to ABS' semantics it should continue right away, hence this test.
  I'.when empty $
    callCC (\ k -> do
                  _ <- I'.liftIO $ forkIO (do
                                    _ <- I'.readMVar mvar    -- wait for future to be resolved
                                    atomically $ writeTQueue thisMailBox (k ()))
                  back' obj)


{-# INLINABLE get_i #-}
get_i :: Obj' this -> RFut -> Process Int
get_i (Obj' _ (Cog thisSleepTable _)) rfut = do
  (bt,ft,ct) <- I'.liftIO $ I'.readIORef thisSleepTable
  case IM.lookup rfut ft of
    Just (res, _) -> do
      I'.liftIO $ I'.writeIORef thisSleepTable (bt, IM.delete rfut ft, ct)
      return res
    Nothing -> receiveWait [matchIf ((\ (_,rfut') -> rfut == rfut') :: (Int,Int) -> Bool) 
                                    (\ (res,_) -> return res)
                           ]

{-# INLINABLE request_i #-}
request_i :: Obj' Worker -> Int -> RObj -> Process RFut
request_i (Obj' _ (Cog thisSleepTable _ )) param callee = do
  (bt, ft, ct) <- I'.liftIO $ I'.readIORef thisSleepTable
  I'.liftIO $ I'.writeIORef thisSleepTable (bt,ft,ct+1)
  self <- getSelfPid
  callee `send` (self, param, ct)
  return ct

{-# INLINABLE requests_i #-}
requests_i:: List Int -> List Int -> Int -> RObj -> Process Unit
requests_i param1 param2 param3 callee = callee `send` (param1,param2,param3)
          

{-# INLINABLE delegates__i #-}
delegates__i:: List Int -> List Int -> RObj -> Process Unit
delegates__i param1 param2 callee = callee `send` (param1,param2)


{-# ILNINABLE init_i #-}
init_i :: Obj' this -> [RObj] -> RObj -> Process RFut
init_i (Obj' _ (Cog thisSleepTable _ )) param callee = do
  (bt, ft, ct) <- I'.liftIO $ I'.readIORef thisSleepTable
  I'.liftIO $ I'.writeIORef thisSleepTable (bt,ft,ct+1)
  callee `send` (param,ct)
  return ct


{-# INLINABLE run_i #-}
run_i :: Obj' this -> RObj -> Process RFut
run_i (Obj' _ (Cog thisSleepTable _ ))callee = do
  (bt, ft, ct) <- I'.liftIO $ I'.readIORef thisSleepTable
  I'.liftIO $ I'.writeIORef thisSleepTable (bt,ft,ct+1)
  callee `send` ct
  return ct


{-# INLINABLE await_i #-}
await_i :: Obj' Worker -> RFut -> ABS' ()
await_i obj@(Obj' _ thisCog@(Cog thisSleepTable _)) rfut = do
  (bt,ft,ct) <- I'.liftIO $ I'.readIORef thisSleepTable
  I'.when (rfut `IM.notMember` ft) $ callCC (\ k -> do
    I'.liftIO $ I'.writeIORef thisSleepTable (bt, IM.insert rfut (I'.undefined, k ()) ft, ct)
    back' obj
    )

back' :: Obj' Worker -> ABS' ()
back' obj@(Obj' _ thisCog@(Cog thisSleepTable thisMailBox)) = do
  st@(bt,ft,ct) <- I'.liftIO $ I'.readIORef thisSleepTable
  (mwoken, st') <- I'.liftIO $ findWoken st                                                  
  case mwoken of
    Nothing -> I'.join $ I'.lift $ receiveWait
      [
        match ((\ 
                -- request
                (caller :: ProcessId,param :: Int,rfut :: RFut) -> do
                  I'.liftIO (putStrLn "request received")
                  return (request param obj >>= (\ res -> I'.lift (caller `send` (res,rfut)) >> back' obj))
                ))
      , match ((\ 
                -- response
                (res,rfut) -> do
                  I'.liftIO (putStrLn "future resolved")
                  case IM.lookup rfut ft of
                    Just (_,k) -> do
                      I'.liftIO $ I'.writeIORef thisSleepTable (bt,IM.insert rfut (res,I'.undefined) ft, ct)
                      return k
                    Nothing -> do
                      I'.liftIO $ I'.writeIORef thisSleepTable (bt,IM.insert rfut (res,I'.undefined) ft, ct)
                      return (back' obj)
              )) -- :: Either (Int,Int) (Int,Int) -> Process (ABS' ()))
      , match ((\ 
                -- delegates_
                (param1,param2) -> do
                   I'.liftIO (putStrLn "delegates_ received")
                   return (delegates_ param1 param2 obj >> back' obj)
              ))
      , match ((\ 
                -- requests
                (param1,param2,param3) -> do
                   I'.liftIO (putStrLn "requests received")
                   return (requests param1 param2 param3 obj >> back' obj)
              ))
      , matchSTM (readTQueue thisMailBox) return
      ]
    Just woken -> do
                I'.liftIO $ I'.writeIORef thisSleepTable st' -- the sleep-table was modified, so write it back
                woken

-- unoptimized suspend
suspend :: Obj' Worker -> ABS' ()
suspend obj@(Obj' _ (Cog _ thisMailBox)) = callCC 
  (\ k -> do
              I'.liftIO (atomically $ writeTQueue thisMailBox (k ()))
              back' obj)

-- remotable
new_i :: (Int,Int,ProcessId) -- worker class params + master 
      -> Process ()
new_i (workerId,size,master) = do
  -- create the cog
  newCogSleepTable <- I'.liftIO $ I'.newIORef ([], IM.empty, 0)
  newCogMailBox <- I'.liftIO $ newTQueueIO
  let newCog = Cog newCogSleepTable newCogMailBox
  -- create the object
  newObj'Contents <- I'.liftIO $ I'.newIORef (smart'Worker workerId size)
  let newObj' = Obj' newObj'Contents newCog

  -- the real init
  I'.liftIO $ init'Worker newObj'

  -- the init_
  (workers,rfut) <- expect :: Process ([RObj], RFut)
  
  evalContT $ do
    init_ workers newObj'
    I'.lift $ master `send` (-1 :: Int,rfut)

    -- the run_
    rfut' <- I'.lift $ expect :: ABS' RFut
    run_ newObj'
    I'.lift $ master `send` (-2 :: Int, rfut')
  
    back' newObj' 
remotable ['new_i]


{-# INLINE main_is' #-}
-- | This function takes an ABS'' main function in the module and executes the ABS' program.
--
-- Note the mainABS' function expects a this object as input. This is only for unifying the method-block generation;
-- the code-generator will safely catch if a main contains calls to this. This runtime, however, does not do such checks;
-- if the user passes a main that uses this, the program will err.
--main_is' :: (Obj' contents -> ABS' ()) -> IO ()
main_is' mainABS' = do
 backend <- initializeBackend (ip cmdOpt) (port cmdOpt) (__remoteTable initRemoteTable)
 if master cmdOpt
  then do
    mb <- newTQueueIO
    st <- I'.newIORef ([],IM.empty,0)     
    startMaster backend (\ peers -> do
      I'.liftIO (print $ "Slaves:" ++ I'.show peers)
      evalContT $ (mainABS' peers $ Obj' (I'.error "runtime error: the main ABS' block tried to call 'this'") (Cog st mb)))
  else startSlave backend



main
  = main_is'
      (\ peers this ->
         do i :: IORef' Int <- I'.liftIO (I'.newIORef (workers))
            w :: IORef' RObj <- I'.liftIO(I'.newIORef I'.undefined)
            -- w :: IORef' IWorker <- I'.liftIO (I'.newIORef (IWorker null))
            size :: IORef' Int <- I'.liftIO
                                    (I'.newIORef (div ((num) - ((d) + 1)) (workers)))
            off :: IORef' Int <- I'.liftIO
                                   (I'.newIORef =<<
                                      ((-) <$!>
                                         ((-) <$!> (I'.pure num) <*>
                                            ((+) <$!> (I'.pure d) <*> I'.pure 1))
                                         <*>
                                         ((*) <$!> (I'.fromIntegral <$!> I'.readIORef size) <*>
                                            (I'.pure workers))))
            self <- I'.lift getSelfPid
            ws :: IORef' (List RObj) <- I'.liftIO(I'.newIORef [])
            -- ws :: IORef' (List IWorker) <- I'.liftIO (I'.newIORef [])
            while
              ((>) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*> I'.pure 0)
              (do if' <- I'.liftIO
                           (((>=) <$!> (I'.fromIntegral <$!> I'.readIORef off) <*>
                               (I'.fromIntegral <$!> I'.readIORef i)))
                  if if' then
                      (I'.liftIO . I'.writeIORef w) =<< (I'.liftIO (I'.readIORef i) >>= \ i' ->
                                              I'.liftIO (I'.readIORef size) >>= \ size' ->
                                                I'.lift (spawn (nth peers (i'-1)) ($(mkClosure 'new_i) (i', (size' + 1)*d, self))))
                    -- do I'.liftIO
                    --      ((I'.writeIORef w . IWorker) =<<
                    --         (new init'Worker =<<
                    --            I'.pure smart'Worker <*> (I'.fromIntegral <$!> I'.readIORef i) <*>
                    --              ((*) <$!>
                    --                 ((+) <$!> (I'.fromIntegral <$!> I'.readIORef size) <*>
                    --                    I'.pure 1)
                    --                 <*> (I'.pure d))))
                    else
                      (I'.liftIO . I'.writeIORef w) =<< (I'.liftIO (I'.readIORef i) >>= \ i' ->
                                              I'.liftIO (I'.readIORef size) >>= \ size' ->
                                                I'.lift (spawn (nth peers (i'-1)) ($(mkClosure 'new_i) (i', size'*d, self))))

                    -- do I'.liftIO
                    --      ((I'.writeIORef w . IWorker) =<<
                    --         (new init'Worker =<<
                    --            I'.pure smart'Worker <*> (I'.fromIntegral <$!> I'.readIORef i) <*>
                    --              ((*) <$!> (I'.fromIntegral <$!> I'.readIORef size) <*>
                    --                 (I'.pure d))))
                  I'.liftIO
                    (I'.writeIORef ws =<<
                       ((:) <$!> (up' <$!> I'.readIORef w) <*> I'.readIORef ws))
                  I'.liftIO
                    (I'.writeIORef i =<<
                       ((-) <$!> (I'.fromIntegral <$!> I'.readIORef i) <*> I'.pure 1)))
            ff :: IORef' RFut <- I'.liftIO(I'.newIORef I'.undefined)
            ws_ :: IORef' (List RObj) <- I'.liftIO
                                              (I'.newIORef =<< I'.readIORef ws)
            fs :: IORef' (List RFut) <- I'.liftIO(I'.newIORef [])
            -- ff :: IORef' (Fut Unit) <- I'.liftIO (I'.newIORef nullFuture')
            -- ws_ :: IORef' (List IWorker) <- I'.liftIO
            --                                   (I'.newIORef =<< I'.readIORef ws)
            -- fs :: IORef' (List (Fut Unit)) <- I'.liftIO (I'.newIORef [])
            while ((not) <$!> ((==) <$!> I'.readIORef ws_ <*> I'.pure []))
              (do I'.liftIO
                    (I'.writeIORef w =<< (I'.pure head <*> I'.readIORef ws_))
                  (I'.liftIO . I'.writeIORef ff) =<<
                          (I'.liftIO (I'.readIORef w) >>= \ w' -> I'.liftIO (I'.readIORef ws) >>= \ ws' ->
                                                                    I'.lift (init_i this ws' w')
                    )
                  -- I'.liftIO
                  --   (I'.writeIORef ff =<<
                  --      ((\ (IWorker obj') ->
                  --          (obj' <!>) =<< I'.pure init_ <*> I'.readIORef ws)
                  --         =<< I'.readIORef w))
                  I'.liftIO
                    (I'.writeIORef fs =<<
                       ((:) <$!> I'.readIORef ff <*> I'.readIORef fs))
                  I'.liftIO
                    (I'.writeIORef ws_ =<< (I'.pure tail <*> I'.readIORef ws_)))
            while ((not) <$!> ((==) <$!> I'.readIORef fs <*> I'.pure []))
              (do _ <- I'.lift(get_i this =<< (I'.pure head <*> I'.liftIO (I'.readIORef fs)))
                  -- _ <- I'.liftIO (get =<< (I'.pure head <*> I'.readIORef fs))
                  I'.liftIO (I'.writeIORef fs =<< (I'.pure tail <*> I'.readIORef fs)))
            I'.liftIO (println "START RUNNING")
            t1 :: IORef' TimeSpec <- I'.liftIO
                                       (I'.newIORef =<<
                                          (I'.join ((I'.pure getTime <*> I'.pure Monotonic))))
            while ((not) <$!> ((==) <$!> I'.readIORef ws <*> I'.pure []))
              (do I'.liftIO
                    (I'.writeIORef w =<< (I'.pure head <*> I'.readIORef ws))
                  (I'.liftIO . I'.writeIORef ff) =<< (I'.liftIO (I'.readIORef w) >>= \ w' ->
                      I'.lift (run_i this w')
                    )
                  -- I'.liftIO
                  --   (I'.writeIORef ff =<<
                  --      ((\ (IWorker obj') -> (obj' <!> run_)) =<< I'.readIORef w))
                  I'.liftIO
                    (I'.writeIORef fs =<<
                       ((:) <$!> I'.readIORef ff <*> I'.readIORef fs))
                  I'.liftIO (I'.writeIORef ws =<< (I'.pure tail <*> I'.readIORef ws)))
            while ((not) <$!> ((==) <$!> I'.readIORef fs <*> I'.pure []))
              (do _ <- I'.lift(get_i this =<< (I'.pure head <*> I'.liftIO (I'.readIORef fs)))
                  -- _ <- I'.liftIO (get =<< (I'.pure head <*> I'.readIORef fs))
                  I'.liftIO (I'.writeIORef fs =<< (I'.pure tail <*> I'.readIORef fs)))
            I'.liftIO
              (println =<<
                 (I'.pure toString <*>
                    (I'.pure diff <*>
                       (I'.join ((I'.pure getTime <*> I'.pure Monotonic)))
                       <*> I'.readIORef t1)))
            I'.liftIO (println "END"))


