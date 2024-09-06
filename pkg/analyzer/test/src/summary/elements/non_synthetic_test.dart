// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../dart/resolution/node_text_expectations.dart';
import '../elements_base.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NonSyntheticElementTest_keepLinking);
    defineReflectiveTests(NonSyntheticElementTest_fromBytes);
    defineReflectiveTests(UpdateNodeTextExpectations);
  });
}

abstract class NonSyntheticElementTest extends ElementsBaseTest {
  test_nonSynthetic_class_field() async {
    var library = await buildLibrary(r'''
class C {
  int foo = 0;
}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          enclosingElement: <testLibraryFragment>
          fields
            foo @16
              reference: <testLibraryFragment>::@class::C::@field::foo
              enclosingElement: <testLibraryFragment>::@class::C
              type: int
              shouldUseTypeForInitializerInference: true
              nonSynthetic: <testLibraryFragment>::@class::C::@field::foo
          constructors
            synthetic @-1
              reference: <testLibraryFragment>::@class::C::@constructor::new
              enclosingElement: <testLibraryFragment>::@class::C
              nonSynthetic: <testLibraryFragment>::@class::C
          accessors
            synthetic get foo @-1
              reference: <testLibraryFragment>::@class::C::@getter::foo
              enclosingElement: <testLibraryFragment>::@class::C
              returnType: int
              nonSynthetic: <testLibraryFragment>::@class::C::@field::foo
            synthetic set foo= @-1
              reference: <testLibraryFragment>::@class::C::@setter::foo
              enclosingElement: <testLibraryFragment>::@class::C
              parameters
                requiredPositional _foo @-1
                  type: int
                  nonSynthetic: <testLibraryFragment>::@class::C::@field::foo
              returnType: void
              nonSynthetic: <testLibraryFragment>::@class::C::@field::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          fields
            foo @16
              reference: <testLibraryFragment>::@class::C::@field::foo
              enclosingFragment: <testLibraryFragment>::@class::C
              getter2: <testLibraryFragment>::@class::C::@getter::foo
              setter2: <testLibraryFragment>::@class::C::@setter::foo
          constructors
            synthetic new @-1
              reference: <testLibraryFragment>::@class::C::@constructor::new
              enclosingFragment: <testLibraryFragment>::@class::C
          getters
            get foo @-1
              reference: <testLibraryFragment>::@class::C::@getter::foo
              enclosingFragment: <testLibraryFragment>::@class::C
          setters
            set foo= @-1
              reference: <testLibraryFragment>::@class::C::@setter::foo
              enclosingFragment: <testLibraryFragment>::@class::C
              parameters
                _foo @-1
  classes
    class C
      reference: <testLibraryFragment>::@class::C
      enclosingElement2: <testLibrary>
      firstFragment: <testLibraryFragment>::@class::C
      fields
        foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@class::C
          type: int
          firstFragment: <testLibraryFragment>::@class::C::@field::foo
          getter: <none>
          setter: <none>
      constructors
        synthetic new
          reference: <none>
          firstFragment: <testLibraryFragment>::@class::C::@constructor::new
      getters
        synthetic get foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@class::C
          firstFragment: <testLibraryFragment>::@class::C::@getter::foo
      setters
        synthetic set foo=
          reference: <none>
          enclosingElement: <testLibraryFragment>::@class::C
          parameters
            requiredPositional _foo
              reference: <none>
              type: int
          firstFragment: <testLibraryFragment>::@class::C::@setter::foo
''');
  }

  test_nonSynthetic_class_getter() async {
    var library = await buildLibrary(r'''
class C {
  int get foo => 0;
}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          enclosingElement: <testLibraryFragment>
          fields
            synthetic foo @-1
              reference: <testLibraryFragment>::@class::C::@field::foo
              enclosingElement: <testLibraryFragment>::@class::C
              type: int
              nonSynthetic: <testLibraryFragment>::@class::C::@getter::foo
          constructors
            synthetic @-1
              reference: <testLibraryFragment>::@class::C::@constructor::new
              enclosingElement: <testLibraryFragment>::@class::C
              nonSynthetic: <testLibraryFragment>::@class::C
          accessors
            get foo @20
              reference: <testLibraryFragment>::@class::C::@getter::foo
              enclosingElement: <testLibraryFragment>::@class::C
              returnType: int
              nonSynthetic: <testLibraryFragment>::@class::C::@getter::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          fields
            foo @-1
              reference: <testLibraryFragment>::@class::C::@field::foo
              enclosingFragment: <testLibraryFragment>::@class::C
              getter2: <testLibraryFragment>::@class::C::@getter::foo
          constructors
            synthetic new @-1
              reference: <testLibraryFragment>::@class::C::@constructor::new
              enclosingFragment: <testLibraryFragment>::@class::C
          getters
            get foo @20
              reference: <testLibraryFragment>::@class::C::@getter::foo
              enclosingFragment: <testLibraryFragment>::@class::C
  classes
    class C
      reference: <testLibraryFragment>::@class::C
      enclosingElement2: <testLibrary>
      firstFragment: <testLibraryFragment>::@class::C
      fields
        synthetic foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@class::C
          type: int
          firstFragment: <testLibraryFragment>::@class::C::@field::foo
          getter: <none>
      constructors
        synthetic new
          reference: <none>
          firstFragment: <testLibraryFragment>::@class::C::@constructor::new
      getters
        get foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@class::C
          firstFragment: <testLibraryFragment>::@class::C::@getter::foo
''');
  }

  test_nonSynthetic_class_setter() async {
    var library = await buildLibrary(r'''
class C {
  set foo(int value) {}
}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          enclosingElement: <testLibraryFragment>
          fields
            synthetic foo @-1
              reference: <testLibraryFragment>::@class::C::@field::foo
              enclosingElement: <testLibraryFragment>::@class::C
              type: int
              nonSynthetic: <testLibraryFragment>::@class::C::@setter::foo
          constructors
            synthetic @-1
              reference: <testLibraryFragment>::@class::C::@constructor::new
              enclosingElement: <testLibraryFragment>::@class::C
              nonSynthetic: <testLibraryFragment>::@class::C
          accessors
            set foo= @16
              reference: <testLibraryFragment>::@class::C::@setter::foo
              enclosingElement: <testLibraryFragment>::@class::C
              parameters
                requiredPositional value @24
                  type: int
                  nonSynthetic: <testLibraryFragment>::@class::C::@setter::foo::@parameter::value
              returnType: void
              nonSynthetic: <testLibraryFragment>::@class::C::@setter::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      classes
        class C @6
          reference: <testLibraryFragment>::@class::C
          fields
            foo @-1
              reference: <testLibraryFragment>::@class::C::@field::foo
              enclosingFragment: <testLibraryFragment>::@class::C
              setter2: <testLibraryFragment>::@class::C::@setter::foo
          constructors
            synthetic new @-1
              reference: <testLibraryFragment>::@class::C::@constructor::new
              enclosingFragment: <testLibraryFragment>::@class::C
          setters
            set foo= @16
              reference: <testLibraryFragment>::@class::C::@setter::foo
              enclosingFragment: <testLibraryFragment>::@class::C
              parameters
                value @24
  classes
    class C
      reference: <testLibraryFragment>::@class::C
      enclosingElement2: <testLibrary>
      firstFragment: <testLibraryFragment>::@class::C
      fields
        synthetic foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@class::C
          type: int
          firstFragment: <testLibraryFragment>::@class::C::@field::foo
          setter: <none>
      constructors
        synthetic new
          reference: <none>
          firstFragment: <testLibraryFragment>::@class::C::@constructor::new
      setters
        set foo=
          reference: <none>
          enclosingElement: <testLibraryFragment>::@class::C
          parameters
            requiredPositional value
              reference: <none>
              type: int
          firstFragment: <testLibraryFragment>::@class::C::@setter::foo
''');
  }

  test_nonSynthetic_enum() async {
    var library = await buildLibrary(r'''
enum E {
  a, b
}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      enums
        enum E @5
          reference: <testLibraryFragment>::@enum::E
          enclosingElement: <testLibraryFragment>
          supertype: Enum
          fields
            static const enumConstant a @11
              reference: <testLibraryFragment>::@enum::E::@field::a
              enclosingElement: <testLibraryFragment>::@enum::E
              type: E
              shouldUseTypeForInitializerInference: false
              constantInitializer
                InstanceCreationExpression
                  constructorName: ConstructorName
                    type: NamedType
                      name: E @-1
                      element: <testLibraryFragment>::@enum::E
                      type: E
                    staticElement: <testLibraryFragment>::@enum::E::@constructor::new
                  argumentList: ArgumentList
                    leftParenthesis: ( @0
                    rightParenthesis: ) @0
                  staticType: E
              nonSynthetic: <testLibraryFragment>::@enum::E::@field::a
            static const enumConstant b @14
              reference: <testLibraryFragment>::@enum::E::@field::b
              enclosingElement: <testLibraryFragment>::@enum::E
              type: E
              shouldUseTypeForInitializerInference: false
              constantInitializer
                InstanceCreationExpression
                  constructorName: ConstructorName
                    type: NamedType
                      name: E @-1
                      element: <testLibraryFragment>::@enum::E
                      type: E
                    staticElement: <testLibraryFragment>::@enum::E::@constructor::new
                  argumentList: ArgumentList
                    leftParenthesis: ( @0
                    rightParenthesis: ) @0
                  staticType: E
              nonSynthetic: <testLibraryFragment>::@enum::E::@field::b
            synthetic static const values @-1
              reference: <testLibraryFragment>::@enum::E::@field::values
              enclosingElement: <testLibraryFragment>::@enum::E
              type: List<E>
              constantInitializer
                ListLiteral
                  leftBracket: [ @0
                  elements
                    SimpleIdentifier
                      token: a @-1
                      staticElement: <testLibraryFragment>::@enum::E::@getter::a
                      staticType: E
                    SimpleIdentifier
                      token: b @-1
                      staticElement: <testLibraryFragment>::@enum::E::@getter::b
                      staticType: E
                  rightBracket: ] @0
                  staticType: List<E>
              nonSynthetic: <testLibraryFragment>::@enum::E
          constructors
            synthetic const @-1
              reference: <testLibraryFragment>::@enum::E::@constructor::new
              enclosingElement: <testLibraryFragment>::@enum::E
              nonSynthetic: <testLibraryFragment>::@enum::E
          accessors
            synthetic static get a @-1
              reference: <testLibraryFragment>::@enum::E::@getter::a
              enclosingElement: <testLibraryFragment>::@enum::E
              returnType: E
              nonSynthetic: <testLibraryFragment>::@enum::E::@field::a
            synthetic static get b @-1
              reference: <testLibraryFragment>::@enum::E::@getter::b
              enclosingElement: <testLibraryFragment>::@enum::E
              returnType: E
              nonSynthetic: <testLibraryFragment>::@enum::E::@field::b
            synthetic static get values @-1
              reference: <testLibraryFragment>::@enum::E::@getter::values
              enclosingElement: <testLibraryFragment>::@enum::E
              returnType: List<E>
              nonSynthetic: <testLibraryFragment>::@enum::E
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      enums
        enum E @5
          reference: <testLibraryFragment>::@enum::E
          fields
            enumConstant a @11
              reference: <testLibraryFragment>::@enum::E::@field::a
              enclosingFragment: <testLibraryFragment>::@enum::E
              getter2: <testLibraryFragment>::@enum::E::@getter::a
            enumConstant b @14
              reference: <testLibraryFragment>::@enum::E::@field::b
              enclosingFragment: <testLibraryFragment>::@enum::E
              getter2: <testLibraryFragment>::@enum::E::@getter::b
            values @-1
              reference: <testLibraryFragment>::@enum::E::@field::values
              enclosingFragment: <testLibraryFragment>::@enum::E
              getter2: <testLibraryFragment>::@enum::E::@getter::values
          constructors
            synthetic const new @-1
              reference: <testLibraryFragment>::@enum::E::@constructor::new
              enclosingFragment: <testLibraryFragment>::@enum::E
          getters
            get a @-1
              reference: <testLibraryFragment>::@enum::E::@getter::a
              enclosingFragment: <testLibraryFragment>::@enum::E
            get b @-1
              reference: <testLibraryFragment>::@enum::E::@getter::b
              enclosingFragment: <testLibraryFragment>::@enum::E
            get values @-1
              reference: <testLibraryFragment>::@enum::E::@getter::values
              enclosingFragment: <testLibraryFragment>::@enum::E
  enums
    enum E
      reference: <testLibraryFragment>::@enum::E
      enclosingElement2: <testLibrary>
      firstFragment: <testLibraryFragment>::@enum::E
      supertype: Enum
      fields
        static const a
          reference: <none>
          enclosingElement: <testLibraryFragment>::@enum::E
          type: E
          firstFragment: <testLibraryFragment>::@enum::E::@field::a
          getter: <none>
        static const b
          reference: <none>
          enclosingElement: <testLibraryFragment>::@enum::E
          type: E
          firstFragment: <testLibraryFragment>::@enum::E::@field::b
          getter: <none>
        synthetic static const values
          reference: <none>
          enclosingElement: <testLibraryFragment>::@enum::E
          type: List<E>
          firstFragment: <testLibraryFragment>::@enum::E::@field::values
          getter: <none>
      constructors
        synthetic const new
          reference: <none>
          firstFragment: <testLibraryFragment>::@enum::E::@constructor::new
      getters
        synthetic static get a
          reference: <none>
          enclosingElement: <testLibraryFragment>::@enum::E
          firstFragment: <testLibraryFragment>::@enum::E::@getter::a
        synthetic static get b
          reference: <none>
          enclosingElement: <testLibraryFragment>::@enum::E
          firstFragment: <testLibraryFragment>::@enum::E::@getter::b
        synthetic static get values
          reference: <none>
          enclosingElement: <testLibraryFragment>::@enum::E
          firstFragment: <testLibraryFragment>::@enum::E::@getter::values
''');
  }

  test_nonSynthetic_mixin_field() async {
    var library = await buildLibrary(r'''
mixin M {
  int foo = 0;
}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      mixins
        mixin M @6
          reference: <testLibraryFragment>::@mixin::M
          enclosingElement: <testLibraryFragment>
          superclassConstraints
            Object
          fields
            foo @16
              reference: <testLibraryFragment>::@mixin::M::@field::foo
              enclosingElement: <testLibraryFragment>::@mixin::M
              type: int
              shouldUseTypeForInitializerInference: true
              nonSynthetic: <testLibraryFragment>::@mixin::M::@field::foo
          accessors
            synthetic get foo @-1
              reference: <testLibraryFragment>::@mixin::M::@getter::foo
              enclosingElement: <testLibraryFragment>::@mixin::M
              returnType: int
              nonSynthetic: <testLibraryFragment>::@mixin::M::@field::foo
            synthetic set foo= @-1
              reference: <testLibraryFragment>::@mixin::M::@setter::foo
              enclosingElement: <testLibraryFragment>::@mixin::M
              parameters
                requiredPositional _foo @-1
                  type: int
                  nonSynthetic: <testLibraryFragment>::@mixin::M::@field::foo
              returnType: void
              nonSynthetic: <testLibraryFragment>::@mixin::M::@field::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      mixins
        mixin M @6
          reference: <testLibraryFragment>::@mixin::M
          fields
            foo @16
              reference: <testLibraryFragment>::@mixin::M::@field::foo
              enclosingFragment: <testLibraryFragment>::@mixin::M
              getter2: <testLibraryFragment>::@mixin::M::@getter::foo
              setter2: <testLibraryFragment>::@mixin::M::@setter::foo
          getters
            get foo @-1
              reference: <testLibraryFragment>::@mixin::M::@getter::foo
              enclosingFragment: <testLibraryFragment>::@mixin::M
          setters
            set foo= @-1
              reference: <testLibraryFragment>::@mixin::M::@setter::foo
              enclosingFragment: <testLibraryFragment>::@mixin::M
              parameters
                _foo @-1
  mixins
    mixin M
      reference: <testLibraryFragment>::@mixin::M
      enclosingElement2: <testLibrary>
      firstFragment: <testLibraryFragment>::@mixin::M
      superclassConstraints
        Object
      fields
        foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@mixin::M
          type: int
          firstFragment: <testLibraryFragment>::@mixin::M::@field::foo
          getter: <none>
          setter: <none>
      getters
        synthetic get foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@mixin::M
          firstFragment: <testLibraryFragment>::@mixin::M::@getter::foo
      setters
        synthetic set foo=
          reference: <none>
          enclosingElement: <testLibraryFragment>::@mixin::M
          parameters
            requiredPositional _foo
              reference: <none>
              type: int
          firstFragment: <testLibraryFragment>::@mixin::M::@setter::foo
''');
  }

  test_nonSynthetic_mixin_getter() async {
    var library = await buildLibrary(r'''
mixin M {
  int get foo => 0;
}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      mixins
        mixin M @6
          reference: <testLibraryFragment>::@mixin::M
          enclosingElement: <testLibraryFragment>
          superclassConstraints
            Object
          fields
            synthetic foo @-1
              reference: <testLibraryFragment>::@mixin::M::@field::foo
              enclosingElement: <testLibraryFragment>::@mixin::M
              type: int
              nonSynthetic: <testLibraryFragment>::@mixin::M::@getter::foo
          accessors
            get foo @20
              reference: <testLibraryFragment>::@mixin::M::@getter::foo
              enclosingElement: <testLibraryFragment>::@mixin::M
              returnType: int
              nonSynthetic: <testLibraryFragment>::@mixin::M::@getter::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      mixins
        mixin M @6
          reference: <testLibraryFragment>::@mixin::M
          fields
            foo @-1
              reference: <testLibraryFragment>::@mixin::M::@field::foo
              enclosingFragment: <testLibraryFragment>::@mixin::M
              getter2: <testLibraryFragment>::@mixin::M::@getter::foo
          getters
            get foo @20
              reference: <testLibraryFragment>::@mixin::M::@getter::foo
              enclosingFragment: <testLibraryFragment>::@mixin::M
  mixins
    mixin M
      reference: <testLibraryFragment>::@mixin::M
      enclosingElement2: <testLibrary>
      firstFragment: <testLibraryFragment>::@mixin::M
      superclassConstraints
        Object
      fields
        synthetic foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@mixin::M
          type: int
          firstFragment: <testLibraryFragment>::@mixin::M::@field::foo
          getter: <none>
      getters
        get foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@mixin::M
          firstFragment: <testLibraryFragment>::@mixin::M::@getter::foo
''');
  }

  test_nonSynthetic_mixin_setter() async {
    var library = await buildLibrary(r'''
mixin M {
  set foo(int value) {}
}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      mixins
        mixin M @6
          reference: <testLibraryFragment>::@mixin::M
          enclosingElement: <testLibraryFragment>
          superclassConstraints
            Object
          fields
            synthetic foo @-1
              reference: <testLibraryFragment>::@mixin::M::@field::foo
              enclosingElement: <testLibraryFragment>::@mixin::M
              type: int
              nonSynthetic: <testLibraryFragment>::@mixin::M::@setter::foo
          accessors
            set foo= @16
              reference: <testLibraryFragment>::@mixin::M::@setter::foo
              enclosingElement: <testLibraryFragment>::@mixin::M
              parameters
                requiredPositional value @24
                  type: int
                  nonSynthetic: <testLibraryFragment>::@mixin::M::@setter::foo::@parameter::value
              returnType: void
              nonSynthetic: <testLibraryFragment>::@mixin::M::@setter::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      mixins
        mixin M @6
          reference: <testLibraryFragment>::@mixin::M
          fields
            foo @-1
              reference: <testLibraryFragment>::@mixin::M::@field::foo
              enclosingFragment: <testLibraryFragment>::@mixin::M
              setter2: <testLibraryFragment>::@mixin::M::@setter::foo
          setters
            set foo= @16
              reference: <testLibraryFragment>::@mixin::M::@setter::foo
              enclosingFragment: <testLibraryFragment>::@mixin::M
              parameters
                value @24
  mixins
    mixin M
      reference: <testLibraryFragment>::@mixin::M
      enclosingElement2: <testLibrary>
      firstFragment: <testLibraryFragment>::@mixin::M
      superclassConstraints
        Object
      fields
        synthetic foo
          reference: <none>
          enclosingElement: <testLibraryFragment>::@mixin::M
          type: int
          firstFragment: <testLibraryFragment>::@mixin::M::@field::foo
          setter: <none>
      setters
        set foo=
          reference: <none>
          enclosingElement: <testLibraryFragment>::@mixin::M
          parameters
            requiredPositional value
              reference: <none>
              type: int
          firstFragment: <testLibraryFragment>::@mixin::M::@setter::foo
''');
  }

  test_nonSynthetic_unit_getter() async {
    var library = await buildLibrary(r'''
int get foo => 0;
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      topLevelVariables
        synthetic static foo @-1
          reference: <testLibraryFragment>::@topLevelVariable::foo
          enclosingElement: <testLibraryFragment>
          type: int
          nonSynthetic: <testLibraryFragment>::@getter::foo
      accessors
        static get foo @8
          reference: <testLibraryFragment>::@getter::foo
          enclosingElement: <testLibraryFragment>
          returnType: int
          nonSynthetic: <testLibraryFragment>::@getter::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      topLevelVariables
        synthetic foo @-1
          reference: <testLibraryFragment>::@topLevelVariable::foo
          enclosingFragment: <testLibraryFragment>
          getter2: <testLibraryFragment>::@getter::foo
      getters
        get foo @8
          reference: <testLibraryFragment>::@getter::foo
          enclosingFragment: <testLibraryFragment>
  topLevelVariables
    synthetic foo
      reference: <none>
      enclosingElement2: <testLibrary>
      type: int
      firstFragment: <testLibraryFragment>::@topLevelVariable::foo
      getter: <none>
  getters
    static get foo
      reference: <none>
      enclosingElement: <testLibrary>
      firstFragment: <testLibraryFragment>::@getter::foo
''');
  }

  test_nonSynthetic_unit_getterSetter() async {
    var library = await buildLibrary(r'''
int get foo => 0;
set foo(int value) {}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      topLevelVariables
        synthetic static foo @-1
          reference: <testLibraryFragment>::@topLevelVariable::foo
          enclosingElement: <testLibraryFragment>
          type: int
          nonSynthetic: <testLibraryFragment>::@getter::foo
      accessors
        static get foo @8
          reference: <testLibraryFragment>::@getter::foo
          enclosingElement: <testLibraryFragment>
          returnType: int
          nonSynthetic: <testLibraryFragment>::@getter::foo
        static set foo= @22
          reference: <testLibraryFragment>::@setter::foo
          enclosingElement: <testLibraryFragment>
          parameters
            requiredPositional value @30
              type: int
              nonSynthetic: <testLibraryFragment>::@setter::foo::@parameter::value
          returnType: void
          nonSynthetic: <testLibraryFragment>::@setter::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      topLevelVariables
        synthetic foo @-1
          reference: <testLibraryFragment>::@topLevelVariable::foo
          enclosingFragment: <testLibraryFragment>
          getter2: <testLibraryFragment>::@getter::foo
          setter2: <testLibraryFragment>::@setter::foo
      getters
        get foo @8
          reference: <testLibraryFragment>::@getter::foo
          enclosingFragment: <testLibraryFragment>
      setters
        set foo= @22
          reference: <testLibraryFragment>::@setter::foo
          enclosingFragment: <testLibraryFragment>
          parameters
            value @30
  topLevelVariables
    synthetic foo
      reference: <none>
      enclosingElement2: <testLibrary>
      type: int
      firstFragment: <testLibraryFragment>::@topLevelVariable::foo
      getter: <none>
      setter: <none>
  getters
    static get foo
      reference: <none>
      enclosingElement: <testLibrary>
      firstFragment: <testLibraryFragment>::@getter::foo
  setters
    static set foo=
      reference: <none>
      enclosingElement: <testLibrary>
      parameters
        requiredPositional value
          reference: <none>
          type: int
      firstFragment: <testLibraryFragment>::@setter::foo
''');
  }

  test_nonSynthetic_unit_setter() async {
    var library = await buildLibrary(r'''
set foo(int value) {}
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      topLevelVariables
        synthetic static foo @-1
          reference: <testLibraryFragment>::@topLevelVariable::foo
          enclosingElement: <testLibraryFragment>
          type: int
          nonSynthetic: <testLibraryFragment>::@setter::foo
      accessors
        static set foo= @4
          reference: <testLibraryFragment>::@setter::foo
          enclosingElement: <testLibraryFragment>
          parameters
            requiredPositional value @12
              type: int
              nonSynthetic: <testLibraryFragment>::@setter::foo::@parameter::value
          returnType: void
          nonSynthetic: <testLibraryFragment>::@setter::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      topLevelVariables
        synthetic foo @-1
          reference: <testLibraryFragment>::@topLevelVariable::foo
          enclosingFragment: <testLibraryFragment>
          setter2: <testLibraryFragment>::@setter::foo
      setters
        set foo= @4
          reference: <testLibraryFragment>::@setter::foo
          enclosingFragment: <testLibraryFragment>
          parameters
            value @12
  topLevelVariables
    synthetic foo
      reference: <none>
      enclosingElement2: <testLibrary>
      type: int
      firstFragment: <testLibraryFragment>::@topLevelVariable::foo
      setter: <none>
  setters
    static set foo=
      reference: <none>
      enclosingElement: <testLibrary>
      parameters
        requiredPositional value
          reference: <none>
          type: int
      firstFragment: <testLibraryFragment>::@setter::foo
''');
  }

  test_nonSynthetic_unit_variable() async {
    var library = await buildLibrary(r'''
int foo = 0;
''');
    configuration.withNonSynthetic = true;
    checkElementText(library, r'''
library
  reference: <testLibrary>
  definingUnit: <testLibraryFragment>
  units
    <testLibraryFragment>
      enclosingElement: <testLibrary>
      topLevelVariables
        static foo @4
          reference: <testLibraryFragment>::@topLevelVariable::foo
          enclosingElement: <testLibraryFragment>
          type: int
          shouldUseTypeForInitializerInference: true
          nonSynthetic: <testLibraryFragment>::@topLevelVariable::foo
      accessors
        synthetic static get foo @-1
          reference: <testLibraryFragment>::@getter::foo
          enclosingElement: <testLibraryFragment>
          returnType: int
          nonSynthetic: <testLibraryFragment>::@topLevelVariable::foo
        synthetic static set foo= @-1
          reference: <testLibraryFragment>::@setter::foo
          enclosingElement: <testLibraryFragment>
          parameters
            requiredPositional _foo @-1
              type: int
              nonSynthetic: <testLibraryFragment>::@topLevelVariable::foo
          returnType: void
          nonSynthetic: <testLibraryFragment>::@topLevelVariable::foo
----------------------------------------
library
  reference: <testLibrary>
  fragments
    <testLibraryFragment>
      topLevelVariables
        foo @4
          reference: <testLibraryFragment>::@topLevelVariable::foo
          enclosingFragment: <testLibraryFragment>
          getter2: <testLibraryFragment>::@getter::foo
          setter2: <testLibraryFragment>::@setter::foo
      getters
        get foo @-1
          reference: <testLibraryFragment>::@getter::foo
          enclosingFragment: <testLibraryFragment>
      setters
        set foo= @-1
          reference: <testLibraryFragment>::@setter::foo
          enclosingFragment: <testLibraryFragment>
          parameters
            _foo @-1
  topLevelVariables
    foo
      reference: <none>
      enclosingElement2: <testLibrary>
      type: int
      firstFragment: <testLibraryFragment>::@topLevelVariable::foo
      getter: <none>
      setter: <none>
  getters
    synthetic static get foo
      reference: <none>
      enclosingElement: <testLibrary>
      firstFragment: <testLibraryFragment>::@getter::foo
  setters
    synthetic static set foo=
      reference: <none>
      enclosingElement: <testLibrary>
      parameters
        requiredPositional _foo
          reference: <none>
          type: int
      firstFragment: <testLibraryFragment>::@setter::foo
''');
  }
}

@reflectiveTest
class NonSyntheticElementTest_fromBytes extends NonSyntheticElementTest {
  @override
  bool get keepLinkingLibraries => false;
}

@reflectiveTest
class NonSyntheticElementTest_keepLinking extends NonSyntheticElementTest {
  @override
  bool get keepLinkingLibraries => true;
}
