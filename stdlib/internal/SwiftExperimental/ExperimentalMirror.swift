//===--- Mirror.swift -----------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2015 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Swift

// These are just here pending review.
/// Return `true` iff `t0` is identical to `t1`
func == (t0: Any.Type, t1: Any.Type) -> Bool {
  return unsafeBitCast(t0, Int.self) == unsafeBitCast(t1, Int.self)
}

/// Return `false` iff `t0` is identical to `t1`
func != (t0: Any.Type, t1: Any.Type) -> Bool {
  return !(t0 == t1)
}

#if _runtime(_ObjC)
// FIXME: ExistentialCollection needs to be supported before this will work
// without the ObjC Runtime.

/// Representation of the sub-structure and optional "display style"
/// of any arbitrary instance.
///
/// Describes the parts---such as stored properties, collection
/// elements, tuple elements, or the active enumeration case---that
/// make up any given instance.  May also supply a "display style"
/// property that suggests how this structure might be rendered.
///
/// Mirrors are used by playgrounds and the debugger.
public struct Mirror {
  /// Representation of descendant classes that don't override
  /// `customMirror()`
  ///
  /// A `CustomReflectable` class can control whether its mirror will
  /// represent descendant classes that don't override
  /// `customMirror()`, by initializing the mirror with a
  /// `DefaultDescendantRepresentation`.
  ///
  /// Note that the effect of this setting goes no deeper than the
  /// nearest descendant class that overrides `customMirror()`, which
  /// in turn can determine representation of *its* descendants.
  public enum DefaultDescendantRepresentation {
  /// Generate a default mirror for descendant classes that don't
  /// override `customMirror()`.  
  ////
  /// This case is the default.
  case Generated

  /// Suppress the representation of descendant classes that don't
  /// override `customMirror()`.  
  ///
  /// This option may be useful at the root of a class cluster, where
  /// implementation details of descendants should generally not be
  /// visible to clients.  
  case Suppressed
  }

  /// Representation of ancestor classes
  ///
  /// A `CustomReflectable` class can control how its mirror will
  /// represent ancestor classes by initializing the mirror with a
  /// `AncestorRepresentation`.
  public enum AncestorRepresentation {
  /// Generate a default mirror for all ancestor classes.  This is the
  /// default behavior.
  ///
  /// Note: this option bypasses any implementation of `customMirror`
  /// that may be supplied by a `CustomReflectable` ancestor, so this
  /// is typically not the right option for a `customMirror`implementation 
    
  /// Generate a default mirror for all ancestor classes.
  ///
  /// This case is the default.
  ///
  /// **Note:** this option generates default mirrors even for
  /// ancestor classes that may implement `CustomReflectable`\ 's
  /// `customMirror` requirement.  To avoid dropping an ancestor class
  /// customization, an override of `customMirror()` should pass
  /// `ancestorRepresentation: .Customized(super.customMirror)` when
  /// initializing its `Mirror`.
  case Generated

  /// Use the nearest ancestor's implementation of `customMirror()` to
  /// create a mirror for that ancestor.  Other classes derived from
  /// such an ancestor are given a default mirror.
  ///
  /// The payload for this option should always be
  /// "`super.customMirror`":
  ///
  /// .. parsed-literal::
  ///
  ///   func customMirror() -> Mirror {
  ///     return Mirror(
  ///       self,
  ///       children: ["someProperty": self.someProperty], 
  ///       ancestorRepresentation: .Customized(**super.customMirror**))
  ///   }
  case Customized(()->Mirror)

  /// Suppress the representation of all ancestor classes.  The
  /// resulting `Mirror`\ 's `superclassMirror()` is `nil`.
  case Suppressed
  }

  /// Reflect upon the given `subject`.
  ///
  /// If the dynamic type of `subject` conforms to `CustomReflectable`,
  /// the resulting mirror is determined by its `customMirror` method.
  /// Otherwise, the result is generated by the language.
  ///
  /// Note: If the dynamic type of `subject` has value semantics,
  /// subsequent mutations of `subject` will not observable in
  /// `Mirror`.  In general, though, the observability of such
  /// mutations is unspecified.
  public init(reflecting subject: Any) {
    if let customized? = subject as? CustomReflectable {
      self = customized.customMirror()
    }
    else {
      self = Mirror(
        legacy: Swift.reflect(subject),
        subjectType: subject.dynamicType)
    }
  }
  
  /// An element of the reflected instance's structure.  The optional
  /// `label` may be used when appropriate, e.g. to represent the name
  /// of a stored property or of an active `enum` case, and will be
  /// used for lookup when `String`\ s are passed to the `descendant`
  /// method.
  public typealias Child = (label: String?, value: Any)

  /// The type used to represent sub-structure.
  ///
  /// Depending on your needs, you may find it useful to "upgrade"
  /// instances of this type to `AnyBidirectionalCollection` or
  /// `AnyRandomAccessCollection`.  For example, to display the last
  /// 20 children of a mirror if they can be accessed efficiently, you
  /// might write::
  ///
  ///   if let b? = AnyBidirectionalCollection(someMirror.children) {
  ///     for i in advance(b.endIndex, -20, b.startIndex)..<b.endIndex {
  ///        println(b[i])
  ///     }
  ///   }
  public typealias Children = AnyForwardCollection<Child>

  /// A suggestion of how a `Mirror`\ 's is to be interpreted.
  ///
  /// Playgrounds and the debugger will show a representation similar
  /// to the one used for instances of the kind indicated by the
  /// `DisplayStyle` case name when the `Mirror` is used for display.
  public enum DisplayStyle {
  case Struct, Class, Enum, Tuple, Optional, Collection, Dictionary, Set
  }

  static func _noSuperclassMirror() -> Mirror? { return nil }

  /// Return the legacy mirror representing the part of `subject`
  /// corresponding to the superclass of `staticSubclass`.
  internal static func _legacyMirror(
    subject: AnyObject, asClass targetSuperclass: AnyClass) -> MirrorType? {
    
    // get a legacy mirror and the most-derived type
    var cls: AnyClass = subject.dynamicType
    var clsMirror = Swift.reflect(subject)

    // Walk up the chain of mirrors/classes until we find staticSubclass
    while let superclass?: AnyClass? = _getSuperclass(cls) {
      let superclassMirror? = clsMirror._superMirror()
        else { break }
      
      if superclass == targetSuperclass { return superclassMirror }
      
      clsMirror = superclassMirror
      cls = superclass
    }
    return nil
  }
  
  internal static func _superclassGenerator<T: Any>(
    subject: T, _ ancestorRepresentation: AncestorRepresentation
  ) -> ()->Mirror? {

    if let subject? = subject as? AnyObject,
      let subjectClass? = T.self as? AnyClass,
      let superclass? = _getSuperclass(subjectClass) {

      switch ancestorRepresentation {
      case .Generated: return {
          self._legacyMirror(subject, asClass: superclass).map {
            Mirror(legacy: $0, subjectType: superclass)
          }
        }
      case .Customized(let makeAncestor):
        return {
          Mirror(subject, subjectClass: superclass, ancestor: makeAncestor())
        }
      case .Suppressed: break
      }
    }
    return Mirror._noSuperclassMirror
  }
  
  /// Represent `subject` with structure described by `children`,
  /// using an optional `displayStyle`.
  ///
  /// If `subject` is not a class instance, `ancestorRepresentation`
  /// and `defaultDescendantRepresentation` are ignored.  Otherwise:
  ///
  /// * `defaultDescendantRepresentation` determines whether descendant
  ///   classes that don't override `customMirror` will be represented.
  ///   By default, a representation is automatically generated.
  ///
  /// * `ancestorRepresentation` determines whether ancestor classes
  ///   will be represented and whether their `customMirror`
  ///   implementations will be used.  By default, a representation is
  ///   automatically generated and any `customMirror` implementation
  ///   is bypassed.  To prevent bypassing customized ancestors,
  ///   `customMirror` overrides should initialize the `Mirror` with ::
  ///
  ///     ancestorRepresentation: .Customized(super.customMirror))
  ///
  /// Note: the traversal protocol modeled by `children`\ 's indices
  /// (`ForwardIndexType`, `BidirectionalIndexType`, or
  /// `RandomAccessIndexType`) is captured so that the resulting
  /// `Mirror`\ 's `children` may be upgraded later.  See the failable
  /// initializers of `AnyBidirectionalCollection` and
  /// `AnyRandomAccessCollection` for details.
  public init<
    T, C: CollectionType where C.Generator.Element == Child
  >(
    _ subject: T,
    children: C,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .Generated,
    defaultDescendantRepresentation: DefaultDescendantRepresentation = .Generated
  ) {
    self._subjectType = T.self
    self._makeSuperclassMirror = Mirror._superclassGenerator(
      subject, ancestorRepresentation)
      
    self.children = Children(children)
    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation = defaultDescendantRepresentation
  }

  /// Represent `subject` with child values given by
  /// `unlabeledChildren`, using an optional `displayStyle`.  The
  /// result's child labels will all be `nil`.
  ///
  /// This initializer is especially useful for the mirrors of
  /// collections, e.g.::
  ///
  ///   extension MyArray : CustomReflectable {
  ///     func customMirror() -> Mirror 
  ///       return Mirror(self, unlabeledChildren: self, displayStyle: .Collection)
  ///     }
  ///   }
  ///
  /// If `subject` is not a class instance, `ancestorRepresentation`
  /// and `defaultDescendantRepresentation` are ignored.  Otherwise:
  ///
  /// * `defaultDescendantRepresentation` determines whether descendant
  ///   classes that don't override `customMirror` will be represented.
  ///   By default, a representation is automatically generated.
  ///
  /// * `ancestorRepresentation` determines whether ancestor classes
  ///   will be represented and whether their `customMirror`
  ///   implementations will be used.  By default, a representation is
  ///   automatically generated and any `customMirror` implementation
  ///   is bypassed.  To prevent bypassing customized ancestors,
  ///   `customMirror` overrides should initialize the `Mirror` with ::
  ///
  ///     ancestorRepresentation: .Customized(super.customMirror))
  ///
  /// Note: the traversal protocol modeled by `children`\ 's indices
  /// (`ForwardIndexType`, `BidirectionalIndexType`, or
  /// `RandomAccessIndexType`) is captured so that the resulting
  /// `Mirror`\ 's `children` may be upgraded later.  See the failable
  /// initializers of `AnyBidirectionalCollection` and
  /// `AnyRandomAccessCollection` for details.
  public init<
    T, C: CollectionType
  >(
    _ subject: T,
    unlabeledChildren: C,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .Generated,
    defaultDescendantRepresentation: DefaultDescendantRepresentation = .Generated
  ) {
    self._subjectType = T.self
    self._makeSuperclassMirror = Mirror._superclassGenerator(
      subject, ancestorRepresentation)
      
    self.children = Children(
      lazy(unlabeledChildren).map { Child(label: nil, value: $0) }
    )
    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation = defaultDescendantRepresentation
  }

  /// Represent `subject` with labeled structure described by
  /// `children`, using an optional `displayStyle`.
  ///
  /// Pass a dictionary literal with `String` keys as `children`.  Be
  /// aware that although an *actual* `Dictionary` is
  /// arbitrarily-ordered, the ordering of the `Mirror`\ 's `children`
  /// will exactly match that of the literal you pass.
  ///
  /// If `subject` is not a class instance, `ancestorRepresentation`
  /// and `defaultDescendantRepresentation` are ignored.  Otherwise:
  ///
  /// * `defaultDescendantRepresentation` determines whether descendant
  ///   classes that don't override `customMirror` will be represented.
  ///   By default, a representation is automatically generated.
  ///
  /// * `ancestorRepresentation` determines whether ancestor classes
  ///   will be represented and whether their `customMirror`
  ///   implementations will be used.  By default, a representation is
  ///   automatically generated and any `customMirror` implementation
  ///   is bypassed.  To prevent bypassing customized ancestors,
  ///   `customMirror` overrides should initialize the `Mirror` with ::
  ///
  ///     ancestorRepresentation: .Customized(super.customMirror))
  ///
  /// Note: The resulting `Mirror`\ 's `children` may be upgraded to
  /// `AnyRandomAccessCollection` later.  See the failable
  /// initializers of `AnyBidirectionalCollection` and
  /// `AnyRandomAccessCollection` for details.
  public init<T>(
    _ subject: T,
    children: DictionaryLiteral<String, Any>,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .Generated,
    defaultDescendantRepresentation: DefaultDescendantRepresentation = .Generated
  ) {
    self._subjectType = T.self
    self._makeSuperclassMirror = Mirror._superclassGenerator(
      subject, ancestorRepresentation)
      
    self.children = Children(
      lazy(children).map { Child(label: $0.0, value: $0.1) }
    )
    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation = defaultDescendantRepresentation
  }
  
  /// A collection of `Child` elements describing the structure of the
  /// reflected subject.
  public let children: Children

  /// Suggests a display style for the reflected subject.
  public let displayStyle: DisplayStyle?

  public func superclassMirror() -> Mirror? {
    return _makeSuperclassMirror()
  }

  internal let _makeSuperclassMirror: ()->Mirror?
  internal let _subjectType: Any.Type
  internal let _defaultDescendantRepresentation: DefaultDescendantRepresentation
}

/// A type that explicitly supplies its own Mirror.
///
/// Instances of any type can be `reflect`\ 'ed upon, but if you are
/// not satisfied with the `Mirror` supplied for your type by default,
/// you can make it conform to `CustomReflectable` and return a custom
/// `Mirror`.
public protocol CustomReflectable {
  /// Return the `Mirror` for `self`.
  ///
  /// Note: if `Self` has value semantics, the `Mirror` should be
  /// unaffected by subsequent mutations of `self`.
  func customMirror() -> Mirror
}

//===--- Addressing -------------------------------------------------------===//

/// A protocol for legitimate arguments to `Mirror`\ 's `descendant`
/// method.
///
/// Do not declare new conformances to this protocol; they will not
/// work as expected.
public protocol MirrorPathType {}
extension IntMax : MirrorPathType {}
extension Int : MirrorPathType {}
extension String : MirrorPathType {}

extension Mirror {
  internal struct _Dummy : CustomReflectable {
    var mirror: Mirror
    func customMirror() -> Mirror { return mirror }
  }
  
  /// Return a specific descendant of the reflected subject, or `nil`
  /// if no such descendant exists.
  ///
  /// A `String` argument selects the first `Child` with a matching label.
  /// An integer argument *n* select the *n*\ th `Child`.  For example::
  ///
  ///   var d = reflect(x).descendant(1, "two", 3)
  ///
  /// is equivalent to:
  ///
  /// .. parsed-literal::
  ///
  ///   var d = nil
  ///   let children = reflect(x).children
  ///   let p0 = advance(children.startIndex, **1**, children.endIndex)
  ///   if p0 != children.endIndex {
  ///     let grandChildren = reflect(children[p0].value).children
  ///     SeekTwo: for g in grandChildren {
  ///       if g.label == **"two"** {
  ///         let greatGrandChildren = reflect(g.value).children
  ///         let p1 = advance(
  ///           greatGrandChildren.startIndex, **3**, 
  ///           greatGrandChildren.endIndex)
  ///         if p1 != endIndex { **d = greatGrandChildren[p1].value** }
  ///         break SeekTwo
  ///       }
  ///     }
  ///   }
  ///
  /// As you can see, complexity for each element of the argument list
  /// depends on the argument type and capabilities of the collection
  /// used to initialize the corresponding subject's parent's mirror.
  /// Each `String` argument results in a linear search.  In short,
  /// this function is suitable for exploring the structure of a
  /// `Mirror` in a REPL or playground, but don't expect it to be
  /// efficient.
  public func descendant(
    first: MirrorPathType, _ rest: MirrorPathType...
  ) -> Any? {
    var result: Any = _Dummy(mirror: self)
    for e in [first] + rest {
      let children = Mirror(reflecting: result).children
      let position: Children.Index
      if let label? = e as? String {
        position = _find(children) { $0.label == label } ?? children.endIndex
      }
      else if let offset? = (e as? Int).map({ IntMax($0) }) ?? (e as? IntMax) {
        position = advance(children.startIndex, offset, children.endIndex)
      }
      else {
        _preconditionFailure(
          "Someone added a conformance to MirrorPathType; that privilege is reserved to the standard library")
      }
      if position == children.endIndex { return nil }
      result = children[position].value
    }
    return result
  }
}

//===--- Legacy MirrorType Support ----------------------------------------===//
extension Mirror.DisplayStyle {
  /// Construct from a legacy `MirrorDisposition`
  internal init?(legacy: MirrorDisposition) {
    switch legacy {
    case .Struct: self = .Struct
    case .Class: self = .Class
    case .Enum: self = .Enum
    case .Tuple: self = .Tuple
    case .Aggregate: return nil
    case .IndexContainer: self = .Collection
    case .KeyContainer: self = .Dictionary
    case .MembershipContainer: self = .Set
    case .Container: preconditionFailure("unused!")
    case .Optional: self = .Optional
    case .ObjCObject: self = .Class
    }
  }
}

internal func _hasType(instance: Any, type: Any.Type) -> Bool {
  return unsafeBitCast(instance.dynamicType, Int.self)
    == unsafeBitCast(type, Int.self) 
}

extension MirrorType {
  final internal func _superMirror() -> MirrorType? {
    return self._legacySuperMirror()
  }
}

/// When constructed using the legacy reflection infrastructure, the
/// resulting `Mirror`\ 's `children` collection will always be
/// upgradable to `AnyRandomAccessCollection` even if it doesn't
/// exhibit appropriate performance. To avoid this pitfall, convert
/// mirrors to use the new style, which only present forward
/// traversal in general.
internal extension Mirror {
  /// An adapter that represents a legacy `MirrorType`\ 's children as
  /// a `Collection` with integer `Index`.  Note that the performance
  /// characterstics of the underlying `MirrorType` may not be
  /// appropriate for random access!  To avoid this pitfall, convert
  /// mirrors to use the new style, which only present forward
  /// traversal in general.
  internal struct LegacyChildren : CollectionType {
    init(_ oldMirror: MirrorType) {
      self._oldMirror = oldMirror
    }

    var startIndex: Int {
      return _oldMirror._superMirror() == nil ? 0 : 1
    }

    var endIndex: Int { return _oldMirror.count }

    subscript(position: Int) -> Child {
      let (label, childMirror) = _oldMirror[position]
      return (label: label, value: childMirror.value)
    }

    func generate() -> IndexingGenerator<LegacyChildren> {
      return IndexingGenerator(self)
    }

    internal let _oldMirror: MirrorType
  }

  /// Initialize for a view of `subject` as `subjectClass`.
  ///
  /// :param: ancestor - a Mirror for a (non-strict) ancestor of
  ///   `subjectClass`, to be injected into the resulting hierarchy.
  ///
  /// :param: legacy - either `nil`, or a legacy mirror for `subject`
  ///    as `subjectClass`.
  internal init(
    _ subject: AnyObject,
    subjectClass: AnyClass,
    ancestor: Mirror,
    legacy legacyMirror: MirrorType? = nil
  ) {
    if ancestor._subjectType == subjectClass
      || ancestor._defaultDescendantRepresentation == .Suppressed {
      self = ancestor
    }
    else {
      let legacyMirror = legacyMirror ?? Mirror._legacyMirror(
        subject, asClass: subjectClass)!
      
      self = Mirror(
        legacy: legacyMirror,
        subjectType: subjectClass,
        makeSuperclassMirror: {
          _getSuperclass(subjectClass).map {
            Mirror(
              subject,
              subjectClass: $0,
              ancestor: ancestor,
              legacy: legacyMirror._legacySuperMirror())
          }
        })
    }
  }

  internal init(
    legacy legacyMirror: MirrorType,
    subjectType: Any.Type,
    makeSuperclassMirror: (()->Mirror?)? = nil
  ) {
    if let makeSuperclassMirror? = makeSuperclassMirror {
      self._makeSuperclassMirror = makeSuperclassMirror
    }
    else if let subjectSuperclass? = _getSuperclass(subjectType) {
      self._makeSuperclassMirror = {
        legacyMirror._superMirror().map {
          Mirror(legacy: $0, subjectType: subjectSuperclass) }
      }
    }
    else {
      self._makeSuperclassMirror = Mirror._noSuperclassMirror
    }
    self._subjectType = subjectType
    self.children = Children(LegacyChildren(legacyMirror))
    self.displayStyle = DisplayStyle(legacy: legacyMirror.disposition)
    self._defaultDescendantRepresentation = .Generated
  }
}

/// Returns the first index `i` in `indices(domain)` such that
/// `predicate(domain[i])` is `true``, or `nil` if
/// `predicate(domain[i])` is `false` for all `i`.
///
/// Complexity: O(\ `count(domain)`\ )
internal func _find<
  C: CollectionType
>(domain: C, predicate: (C.Generator.Element)->Bool) -> C.Index? {
  for i in indices(domain) {
    if predicate(domain[i]) {
      return i
    }
  }
  return nil
}

/*
//===--- QuickLooks -------------------------------------------------------===//

// this typealias implies renaming the existing QuickLookObject to
// PlaygroundQuickLook (since it is an enum, the use of the word
// "Object" is misleading).
public typealias PlaygroundQuickLook = QuickLookObject

extension PlaygroundQuickLook {
  /// Initialize for the given `subject`.
  ///
  /// If the dynamic type of `subject` conforms to
  /// `CustomPlaygroundQuickLookable`, returns the result of calling
  /// its `customPlaygroundQuickLook` method.  Otherwise, returns
  /// a `PlaygroundQuickLook` synthesized for `subject` by the
  /// language.  Note: in some cases the result may be
  /// `.Text(String(reflecting: subject))`.
  ///
  /// Note: If the dynamic type of `subject` has value semantics,
  /// subsequent mutations of `subject` will not observable in
  /// `Mirror`.  In general, though, the observability of such
  /// mutations is unspecified.
  public init(reflecting subject: Any) {
    if let customized? = subject as? CustomPlaygroundQuickLookable {
      self = customized.customPlaygroundQuickLook()
    }
    else {
      if let q? = Swift.reflect(subject).quickLookObject {
        self = q
      }
      else {
        self = .Text(String(reflecting: subject))
      }
    }
  }
}

/// A type that explicitly supplies its own PlaygroundQuickLook.
///
/// Instances of any type can be `reflect`\ 'ed upon, but if you are
/// not satisfied with the `Mirror` supplied for your type by default,
/// you can make it conform to `CustomReflectable` and return a custom
/// `Mirror`.
public protocol CustomPlaygroundQuickLookable {
  /// Return the `Mirror` for `self`.
  ///
  /// Note: if `Self` has value semantics, the `Mirror` should be
  /// unaffected by subsequent mutations of `self`.
  func customPlaygroundQuickLook() -> PlaygroundQuickLook
}

//===--- General Utilities ------------------------------------------------===//
// This component could stand alone, but is used in Mirror's public interface.

/// Represent the ability to pass a dictionary literal in function
/// signatures.
///
/// A function with a `DictionaryLiteral` parameter can be passed a
/// Swift dictionary literal without causing a `Dictionary` to be
/// created.  This capability can be especially important when the
/// order of elements in the literal is significant.
///
/// For example::
///
///   struct IntPairs {
///     var elements: [(Int, Int)]
///     init(_ pairs: DictionaryLiteral<Int,Int>) {
///       elements = Array(pairs)
///     }
///   }
///
///   let x = IntPairs([1:2, 1:1, 3:4, 2:1])
///   println(x.elements)  // [(1, 2), (1, 1), (3, 4), (2, 1)]
public struct DictionaryLiteral<Key, Value> : DictionaryLiteralConvertible {
  /// Store `elements`
  public init(dictionaryLiteral elements: (Key, Value)...) {
    self.elements = elements
  }
  internal let elements: [(Key, Value)]
}

/// `CollectionType` conformance that allows `DictionaryLiteral` to
/// interoperate with the rest of the standard library.
extension DictionaryLiteral : CollectionType {
  /// The position of the first element in a non-empty `DictionaryLiteral`.
  ///
  /// Identical to `endIndex` in an empty `DictionaryLiteral`.
  ///
  /// Complexity: O(1)
  public var startIndex: Int { return 0 }
  
  /// The `DictionaryLiteral`\ 's "past the end" position.
  ///
  /// `endIndex` is not a valid argument to `subscript`, and is always
  /// reachable from `startIndex` by zero or more applications of
  /// `successor()`.
  ///
  /// Complexity: O(1)
  public var endIndex: Int { return elements.endIndex }

  // FIXME: a typealias is needed to prevent <rdar://20248032>
  // why doesn't this need to be public?
  typealias Element = (Key, Value)

  /// Access the element indicated by `position`.
  ///
  /// Requires: `position >= 0 && position < endIndex`.
  ///
  /// Complexity: O(1)
  public subscript(position: Int) -> Element {
    return elements[position]
  }

  /// Return a *generator* over the elements of this *sequence*.  The
  /// *generator*\ 's next element is the first element of the
  /// sequence.
  ///
  /// Complexity: O(1)
  public func generate() -> IndexingGenerator<DictionaryLiteral> {
    return IndexingGenerator(self)
  }
}
*/
#endif

/*
extension String {  
  /// Initialize `self` with the textual representation of `instance`.
  ///
  /// * If `T` conforms to `Streamable`, the result is obtained by
  ///   calling `instance.writeTo(s)` on an empty string s.
  /// * Otherwise, if `T` conforms to `CustomStringConvertible`, the
  ///   result is `instance`\ 's `description`
  /// * Otherwise, if `T` conforms to `CustomDebugStringConvertible`,
  ///   the result is `instance`\ 's `debugDescription`
  /// * Otherwise, an unspecified result is supplied automatically by
  ///   the Swift standard library.
  ///
  /// See Also: `String.init<T>(reflecting: T)`
  public init<T>(_ instance: T) {
    self.init()
    print(instance, &self)
  }

  /// Initialize `self` with a detailed textual representation of
  /// `instance`, suitable for debugging.
  ///
  /// * If `T` conforms to `CustomDebugStringConvertible`, the result
  ///   is `instance`\ 's `debugDescription`
  ///
  /// * Otherwise, if `T` conforms to `CustomStringConvertible`, the result
  ///   is `instance`\ 's `description`
  ///
  /// * Otherwise, if `T` conforms to `Streamable`, the result is
  ///   obtained by calling `instance.writeTo(s)` on an empty string s.
  ///
  /// * Otherwise, an unspecified result is supplied automatically by
  ///   the Swift standard library.
  ///
  /// See Also: `String.init<T>(T)`
  public init<T>(reflecting instance: T) {
    self.init()
    debugPrint(instance, &self)
  }
}
*/
