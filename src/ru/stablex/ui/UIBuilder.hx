package ru.stablex.ui;

import haxe.macro.Context;
import haxe.macro.Expr;
#if macro
import sys.FileSystem;
import sys.io.File;
#else
import ru.stablex.ui.skins.Skin;
import Type;
import nme.text.TextField;
import ru.stablex.ui.widgets.Widget;
#end


#if haxe3
typedef Hash<T> = Map<String,T>;
#end


/**
* Core class. All macro magic lives here
*/
class UIBuilder {
#if macro
    //Regexps for checking attribute types and code generation in xml {
        //checks whether attribute declares event listener
        static private var _erEvent    : EReg = ~/^on-(.+)/i;
        //for replacing @someVar with arguments passed to UIBuilder.buildFn()({arguments})
        static private var _erCodeArg : EReg = ~/(^|[^@])@([._a-z0-9]+)/i;
        //for replacing $ClassName with classes registered through UIBuilder.regClass('fully qualified class name')
        static private var _erCls     : EReg = ~/(^|[^\$])\$([a-z0-9_]+)([^a-z0-9_])/i;
        //for replacing #someId with UIBuilder.get('someId')
        static private var _erId      : EReg = new EReg("(^|[^#])#([a-z0-9_]+)([^a-z0-9_])", "i");
        //for replacing #SomeClass(someId) with UIBuilder.getAs('someId', SomeClass)
        static private var _erCastId  : EReg = new EReg("(^|[^#])#([a-z0-9_]+)\\(([a-z0-9_]+)\\)", "i");
        //for replacing `this` keyword with object currently being processed
        static private var _erThis    : EReg = ~/(^|[^\$])\$this([^a-z0-9_])/i;
        //checks whether we need to create object of specified class (second matched group) for this attribute (first matched group)
        static private var _erAttrCls : EReg = ~/(([-a-z0-9_]+):([a-z0-9_]+))/i;
    //}

    static private var _events  : Hash<Array<String>> = new Hash();
    static private var _imports : Hash<String> = new Hash();

    static private var _initialized : Bool = false;
    //all generated code will be saved in this direcory (see .init() method for details)
    static private var _generatedCodeDir : String = null;

    /**
    * Meta tags processors. Available only in macro step of compilation.
    * These closures should return some valid haxe code,
    * wich will be injected in generated by StablexUI code.
    * Read <a href="http://stablex.ru/ui/doc/#manual/08_Meta_tags.html">manual #8</a> for the list of standart metas and to know how to create custom metas.
    *
    * @param Xml - node of meta tag
    * @param String - variable name of widget, wich has a parent tag for currently processed meta tag
    * @return - valid haxe code to inject in generated code
    */
    static public var meta : Hash<Xml->String->String> = new Hash();
#end


#if !macro
    //Closures for applaying default settings to widgets. Closures created with UIBuilder.init('defaults.xml')
    static public var defaults : Hash<Hash<Widget->Void>> = new Hash();

    //Widgets created with UIBuilder.buildFn() or UIBuilder.create()
    static private var _objects : Hash<Widget> = new Hash();

    //registered skins
    static public var skins : Hash<Void->Skin> = new Hash();

    //For id generator
    static private var _nextId : Int = 0;

    //list of widgets waiting for skin applying
    static private var _skinQueue : List<Widget> = new List();
#end

    /**
    * Set directory to save generated code to. Should be called before .init()
    * If you get any compiler errors on your xml files, you can find corresponding
    * file with generated code to find out what was wrong.
    */
    #if haxe3 macro #else @:macro #end static public function saveCodeTo (dir:String) : Expr {
        var endSlash : EReg = ~/(\/|\\)$/;
        if( !endSlash.match(dir) ){
            dir += '/';
        }
        if( !FileSystem.exists(dir) || !FileSystem.isDirectory(dir) ){
            Err.trigger('Path does not exist or is not a directory: ' + dir);
        }
        UIBuilder._generatedCodeDir = dir;

        return Context.parse('true', Context.currentPos());
    }//function saveCodeTo()


    /**
    * Initializing UIBuilder. Should be called before using any other UIBuilder methods except .reg* methods
    * @param defaultsXmlFile - path to xml file with default settings for widgets
    */
    #if haxe3 macro #else @:macro #end static public function init(defaultsXmlFile:String = null) : Expr {
        var code : String = '\nnme.Lib.current.stage.removeEventListener(nme.events.Event.ENTER_FRAME, ru.stablex.ui.UIBuilder.skinQueue);';
        code += '\nnme.Lib.current.stage.addEventListener(nme.events.Event.ENTER_FRAME, ru.stablex.ui.UIBuilder.skinQueue);';

        if( !UIBuilder._initialized ){
            UIBuilder._initialized = true;

            //registering frequently used events
            UIBuilder.regEvent('enterFrame',  'nme.events.Event.ENTER_FRAME');
            UIBuilder.regEvent('click',       'nme.events.MouseEvent.CLICK',                    'nme.events.MouseEvent');
            UIBuilder.regEvent('mouseDown',   'nme.events.MouseEvent.MOUSE_DOWN',               'nme.events.MouseEvent');
            UIBuilder.regEvent('mouseUp',     'nme.events.MouseEvent.MOUSE_UP',                 'nme.events.MouseEvent');
            UIBuilder.regEvent('display',     'nme.events.Event.ADDED_TO_STAGE');
            UIBuilder.regEvent('create',      'ru.stablex.ui.events.WidgetEvent.CREATE',        'ru.stablex.ui.events.WidgetEvent');
            UIBuilder.regEvent('free',        'ru.stablex.ui.events.WidgetEvent.FREE',          'ru.stablex.ui.events.WidgetEvent');
            UIBuilder.regEvent('resize',      'ru.stablex.ui.events.WidgetEvent.RESIZE',        'ru.stablex.ui.events.WidgetEvent');
            UIBuilder.regEvent('change',      'ru.stablex.ui.events.WidgetEvent.CHANGE',        'ru.stablex.ui.events.WidgetEvent');
            UIBuilder.regEvent('scrollStart', 'ru.stablex.ui.events.WidgetEvent.SCROLL_START',  'ru.stablex.ui.events.WidgetEvent');
            UIBuilder.regEvent('scrollStop',  'ru.stablex.ui.events.WidgetEvent.SCROLL_STOP',   'ru.stablex.ui.events.WidgetEvent');
            UIBuilder.regEvent('drag',        'ru.stablex.ui.events.DndEvent.DRAG',             'ru.stablex.ui.events.DndEvent');
            UIBuilder.regEvent('drop',        'ru.stablex.ui.events.DndEvent.DROP',             'ru.stablex.ui.events.DndEvent');
            UIBuilder.regEvent('receiveDrop', 'ru.stablex.ui.events.DndEvent.RECEIVE',          'ru.stablex.ui.events.DndEvent');
            UIBuilder.regEvent('beforeScroll','ru.stablex.ui.events.ScrollEvent.BEFORE_SCROLL', 'ru.stablex.ui.events.ScrollEvent');

            //registering frequently used classes
            UIBuilder.regClass('ru.stablex.ui.widgets.Text');
            UIBuilder.regClass('ru.stablex.ui.widgets.InputText');
            UIBuilder.regClass('ru.stablex.ui.widgets.Widget');
            UIBuilder.regClass('ru.stablex.ui.widgets.Bmp');
            UIBuilder.regClass('ru.stablex.ui.widgets.Button');
            UIBuilder.regClass('ru.stablex.ui.widgets.StateButton');
            UIBuilder.regClass('ru.stablex.ui.widgets.Toggle');
            UIBuilder.regClass('ru.stablex.ui.widgets.Checkbox');
            UIBuilder.regClass('ru.stablex.ui.widgets.Radio');
            UIBuilder.regClass('ru.stablex.ui.widgets.Box');
            UIBuilder.regClass('ru.stablex.ui.widgets.VBox');
            UIBuilder.regClass('ru.stablex.ui.widgets.HBox');
            UIBuilder.regClass('ru.stablex.ui.widgets.ViewStack');
            UIBuilder.regClass('ru.stablex.ui.widgets.Scroll');
            UIBuilder.regClass('ru.stablex.ui.widgets.Progress');
            UIBuilder.regClass('ru.stablex.ui.widgets.Floating');
            UIBuilder.regClass('ru.stablex.ui.widgets.Options');
            UIBuilder.regClass('ru.stablex.ui.widgets.TabStack');
            UIBuilder.regClass('ru.stablex.ui.widgets.TabPage');
            UIBuilder.regClass('ru.stablex.ui.widgets.Tip');
            UIBuilder.regClass('ru.stablex.ui.widgets.Slider');
            UIBuilder.regClass('ru.stablex.ui.widgets.Switch');
            UIBuilder.regClass('ru.stablex.ui.widgets.Clock');
            UIBuilder.regClass('ru.stablex.ui.events.WidgetEvent');
            UIBuilder.regClass('ru.stablex.ui.events.DndEvent');
            UIBuilder.regClass('ru.stablex.ui.events.ScrollEvent');
            UIBuilder.regClass('ru.stablex.ui.skins.Paint');
            UIBuilder.regClass('ru.stablex.ui.skins.Gradient');
            UIBuilder.regClass('ru.stablex.ui.skins.Tile');
            UIBuilder.regClass('ru.stablex.ui.skins.Slice3');
            UIBuilder.regClass('ru.stablex.ui.skins.Slice9');
            UIBuilder.regClass('ru.stablex.ui.skins.Layer');
            UIBuilder.regClass('ru.stablex.ui.skins.Img');
            UIBuilder.regClass('ru.stablex.ui.layouts.Column');
            UIBuilder.regClass('ru.stablex.ui.layouts.Row');
            UIBuilder.regClass('ru.stablex.ui.transitions.Fade');
            UIBuilder.regClass('ru.stablex.ui.transitions.Slide');
            UIBuilder.regClass('ru.stablex.ui.transitions.Scale');
            UIBuilder.regClass('ru.stablex.ui.UIBuilder');
            UIBuilder.regClass('ru.stablex.ui.Dnd');
            UIBuilder.regClass('ru.stablex.TweenSprite');
            UIBuilder.regClass('ru.stablex.Assets');
            UIBuilder.regClass('nme.events.Event');
            UIBuilder.regClass('nme.events.MouseEvent');
            UIBuilder.regClass('nme.Lib');

            //register default meta processors
            UIBuilder._createCoreMeta();
        }

        //If provided with file for defaults, generate closures for applying defaults to widgets
        if( defaultsXmlFile != null ){
            var root : Xml = Xml.parse( File.getContent(defaultsXmlFile) ).firstElement();
            for(widget in root.elements()){
                code += '\nif( !ru.stablex.ui.UIBuilder.defaults.exists("' + widget.nodeName + '") ) ru.stablex.ui.UIBuilder.defaults.set("' + widget.nodeName + '", new Hash());';
                for(node in widget.elements()){
                    code += '\nru.stablex.ui.UIBuilder.defaults.get("' + widget.nodeName + '").set("' + node.nodeName + '", function(__ui__widget0:ru.stablex.ui.widgets.Widget) : Void {';
                    code += UIBuilder.construct(node, 1, widget.nodeName);
                    code += '\n});';
                }
            }
        }

        code = '(function() : Void {' + code + '})()';
        if( defaultsXmlFile != null ){
            UIBuilder._saveCode(defaultsXmlFile, code);
        }

        return UIBuilder._parse((defaultsXmlFile == null ? 'UIBuilder.hx' : defaultsXmlFile), code);
    }//function _init()

#if macro
    /**
    * Save code generated from specified file
    *
    */
    static private inline function _saveCode (xmlFile:String, code:String) : Void {
        if( UIBuilder._generatedCodeDir != null ){
            xmlFile = StringTools.replace(xmlFile, '\\', '_');
            xmlFile = StringTools.replace(xmlFile, '/', '_');
            xmlFile = StringTools.replace(xmlFile, '.', '_');
            File.saveContent(UIBuilder._generatedCodeDir + xmlFile + '.hx', code);
        }
    }//function _saveCode()


    /**
    * Parse error in xml file
    *
    */
    static private function _parseError (code:String, err:haxe.macro.Error) : Void {
        var pos        : String = Std.string(err.pos);
        var fnameStart : Int = pos.indexOf('(') + 1;
        var fnameEnd   : Int = pos.indexOf(':');

        var line  : Int = Std.parseInt( pos.substring(fnameEnd + 1, pos.indexOf(':', fnameEnd + 1)) );
        var fname : String = pos.substring(fnameStart, fnameEnd);

        var lines : Array<String> = code.split('\n');

        Sys.stderr().writeString( pos.substring(pos.indexOf('(') + 1, pos.indexOf(')')) + ' ' + err.message + '\n' );
        Sys.stderr().writeString( StringTools.replace(lines[line - 1], '\r', '') + '\n' );

        Sys.exit(-1);
    }//function _parseError()


    /**
    * Try to parse this code
    *
    */
    static private inline function _parse (xmlFile:String, code:String) : Expr {
        var expr : Expr = null;
        try{
            expr = Context.parseInlineString(code, Context.makePosition({ min:0, max:0, file:xmlFile}) );
        }catch(e:haxe.macro.Error){
            UIBuilder._parseError(code, e);
        }
        return expr;
    }//function _parse()


    /**
    * Creates basic meta tags processors
    *
    */
    static private function _createCoreMeta() : Void {
        MetaTags.create();
    }//function _createCoreMeta()


    /**
    * Generates code based on Xml object.
    *
    * @throw <type>String</type> if one of used in xml widgets, classes or events was not registered by .regClass() or .regEvent()
    */
    static public function construct (element:Xml, n:Int = 1, zeroElementCls:String = null, wname:String = "__ui__widget") : String{
        //get class for widget
        var cls  : String = UIBuilder._imports.get(zeroElementCls == null ? element.nodeName : zeroElementCls);
        if( cls == null ) Err.trigger('Widget class is not registered: ' + (zeroElementCls == null ? element.nodeName : zeroElementCls));

        var code : String = '';

        if( zeroElementCls != null ){
            code = '\nvar '+ wname + n + ' : ' + cls + ' = cast('+ wname +'0, ' + cls + ');';

        //special properties
        }else{
            code += '\nvar '+ wname + n + ' : ' + cls + ' = new ' + cls + '();';

            //default settings {
                var defaults : String = element.get('defaults');
                if( defaults == null ) {
                    defaults = '"Default"';
                }

                code += '\nif( ru.stablex.ui.UIBuilder.defaults.exists("' + element.nodeName + '") ){';
                code += '\n     var defs = ' + defaults + '.split(",");';
                code += '\n     var defFns = ru.stablex.ui.UIBuilder.defaults.get("' + element.nodeName + '");';
                code += '\n     for(i in 0...defs.length){';
                code += '\n         var defaultsFn : ru.stablex.ui.widgets.Widget->Void = defFns.get(defs[i]);';
                code += '\n         if( defaultsFn != null ) defaultsFn('+ wname + n + ');';
                code += '\n     }';
                code += '\n}';

                // if( defaults != null ){
                //     code += "\n" + wname + n + ".defaults = " + defaults + ";";
                // }
                // code += "\nru.stablex.ui.UIBuilder.applyDefaults(" + wname + n + ");";
            //}
        }
        code += UIBuilder.attr2Haxe(element, wname + n);

        //call .onInitialize method to notify widget that it is initialized
        if( zeroElementCls == null ){
            code += '\n'+ wname + n + '._onInitialize();';
        }

        //if we have nested widgets, generate code for them
        for(node in element.elements()){
            //if this node defines some meta
            if( node.nodeName.indexOf('meta:') == 0 ){
                var meta : String = node.nodeName.substr('meta:'.length);
                var fn   : Xml->String->String = UIBuilder.meta.get(meta);
                if( fn == null ) Err.trigger('Meta processor not found: ' + meta);

                code += fn(node, wname + n);

            //continue ordinary code generation
            }else{
                code += '\n' + UIBuilder.construct(node, n + 1, null, wname);
            }
        }

        //call .onCreate method to notify widget that it is created
        if( zeroElementCls == null ){
            code += '\n'+ wname + n + '._onCreate();';
        }

        //add to parent's display list
        if( n > 1 ){
            code += '\n'+ wname + Std.string(n - 1) + '.addChild('+ wname +'' + n + ');';
        }

        return code;
    }//function construct()


    /**
    * Generate haxe code based on `element` attributes as properties of `obj`
    *
    */
    static public function attr2Haxe (element:Xml, obj:String) : String {

        var attributes : Iterator<String> = element.attributes();
        var post       : Array<String> = [];

        var attr  : String;
        var cls   : String;
        var value : String;

        var code : String = '';

        while( attributes.hasNext() ){
            attr = attributes.next();

            //if this attribute defines class casting, leave it for the end
            if( attr.indexOf(':') != -1 ){
                post.push(attr);
                continue;
            }

            value = element.get(attr);
            //required code replacements
            value = UIBuilder.fillCodeShortcuts(obj, value);

            //if this attribute defines event listener
            if( UIBuilder._erEvent.match(attr) ){
                var event : Array<String> = UIBuilder._events.get( UIBuilder._erEvent.matched(1) );
                if( event == null ) Err.trigger('Event is not registered: ' + UIBuilder._erEvent.matched(1));

                code += '\n' + obj + '.addEventListener('+ event[0] +', function(event:' + event[1] + '){' + value + '});';

            //just apply attribute value to appropriate widget property
            }else{
                //change '-' to '.', so 'someProp-nestedProp' becomes 'someProp.nestedProp'
                attr  = StringTools.replace(attr, '-', '.');

                code += '\n' + obj + '.' + attr + ' = ' + value + ';';
            }
        }//while( attributes.length )

        //process class-casting attributes
        if( post.length > 0 ){
            var props : Hash<Bool> = new Hash();
            var prop  : String;
            var pos   : Int = -1;
            post.sort(UIBuilder._attrClassCastSorter);

            for(i in 0...post.length){
                attr = obj + '.' + post[i];

                //find class start
                while( -1 != (pos = attr.indexOf(':')) ){
                    //find class name
                    cls = attr.substring(pos + 1, attr.indexOf('-', pos));
                    if( !UIBuilder._imports.exists(cls) ) Err.trigger('Class is not registered: ' + cls);
                    cls = UIBuilder._imports.get(cls);

                    //property
                    prop = StringTools.replace(attr.substr(0, pos), '-', '.');

                    //create new object if needed
                    if( !props.exists(prop) ){
                        props.set(prop, true);
                        code += '\nif( !Std.is(' + prop + ', ' + cls + ') ){';
                        code += '\n     ' + prop + ' = new ' + cls + '();';

                        //if this is a widget, we should do all necessary stuff
                        code += '\n     if( Std.is(' + prop + ', ru.stablex.ui.widgets.Widget) ){';
                        code += '\n         var __tmp__ : ru.stablex.ui.widgets.Widget = cast(' + prop + ', ru.stablex.ui.widgets.Widget);';
                        code += '\n         ru.stablex.ui.UIBuilder.applyDefaults(__tmp__);';
                        code += '\n         __tmp__._onInitialize();';
                        code += '\n         __tmp__._onCreate();';
                        code += '\n     }';

                        code += '\n}';
                    }

                    attr = 'cast(' + prop + ', ' + cls + ').' + attr.substr(attr.indexOf('-', pos) + 1);
                }//while()

                //replace remaining `-`-chars
                attr = StringTools.replace(attr, '-', '.');

                code += '\n' + attr + ' = ' + UIBuilder.fillCodeShortcuts(obj, element.get(post[i])) + ';';
            }//for( post )
        }//if( post.length > 0 )

        return code;
    }//function attr2Haxe()


    /**
    * Replace code shortcuts:
    *   $this - replaced with current widget;
    *   $SomeClass - replaced with com.some.package.SomeClass. If registered with UIBuilder.regClass('com.some.package.SomeClass');
    *   #widgetId - replaced with UIBuilder.get('widgetId');
    *   #SomeClass(widgetId) - replaced with UIBuilder.getAs('widgetId', SomeClass);
    *                           SomeClass must be of <type>Class</type>&lt;<type>ru.stablex.ui.widgets.Widget</type>&gt;
    *   @someParam - replaced with arguments.someParam. Arguments can be passed by UIBuilder.buildFn(xmlFile)({arguments});
    */
    static public function fillCodeShortcuts (thisObj:String, code:String) : String{
        var cls    = UIBuilder._erCls;
        var id     = UIBuilder._erId;
        var castId = UIBuilder._erCastId;
        var arg    = UIBuilder._erCodeArg;
        var erThis = UIBuilder._erThis;

        //this
        while( erThis.match(code) ){
            code = erThis.replace(code, '$1' + thisObj+'$2');
        }

        //class names
        while( cls.match(code) ){
            if( !UIBuilder._imports.exists(cls.matched(2)) ) Err.trigger('Class is not imported: ' + cls.matched(2));
            code = cls.replace(code, '$1' + UIBuilder._imports.get(cls.matched(2)) + '$3' );
        }

        //widgets by id as specified class
        while( castId.match(code) ){
            if( !UIBuilder._imports.exists(castId.matched(2)) ) Err.trigger('Class is not imported: ' + castId.matched(2));
            code = castId.replace(code, '$1ru.stablex.ui.UIBuilder.getAs("$3", ' + UIBuilder._imports.get(castId.matched(2)) + ')');
        }

        //widgets by ids
        while( id.match(code) ){
            code = id.replace(code, '$1ru.stablex.ui.UIBuilder.get("$2")$3');
        }

        //arguments
        while( arg.match(code) ){
            code = arg.replace(code, '$1__ui__arguments.$2');
        }

        code = StringTools.replace(code, "##", "#");
        code = StringTools.replace(code, "$$", "$");
        code = StringTools.replace(code, "@@", "@");

        return code;
    }//function fillCodeShortcuts()


    /**
    * Used for sorting attributes with class casting. Mor casts in single attribute -> later processing
    *
    */
    static private function _attrClassCastSorter (attr1:String, attr2:String) : Int {
        //count casts in first attr
        var c1  : Int = 0;
        var pos : Int = 0;
        while( pos < attr1.length && -1 != (pos = attr1.indexOf(':', pos)) ){
            c1 ++;
            pos ++;
        }

        //count casts in second attr
        var c2  : Int = 0;
        var pos : Int = 0;
        while( pos < attr2.length && -1 != (pos = attr2.indexOf(':', pos)) ){
            c2 ++;
            pos ++;
        }

        //less casts => earlier processing
        if( c1 > c2 ){
            return 1;
        }else if( c1 < c2 ){
            return -1;
        }else{
            return 0;
        }
    }//function _attrClassCastSorter()

#end

    /**
    * Generates closure for widget creation. xmlFile - path to xml file with markup.
    * In xml you can use these placeholders:
    *   $this - replaced with current widget;
    *   $SomeClass - replaced with com.some.package.SomeClass. If registered with UIBuilder.regClass('com.some.package.SomeClass');
    *   #widgetId - replaced with UIBuilder.get('widgetId');
    *   #SomeClass(widgetId) - replaced with UIBuilder.getAs('widgetId', SomeClass);
    *                           SomeClass must be of <type>Class</type>&lt;<type>ru.stablex.ui.widgets.Widget</type>&gt;
    *   @someParam - replaced with arguments.someParam. Arguments can be passed like this: UIBuilder.buildFn(xmlFile)({someParam:'some value', someParam2: 3.14});
    *
    * @throw <type>String</type> if .init() was not called before
    * @throw <type>String</type> if one of used in xml widgets, classes or events was not registered by .regClass() or .regEvent()
    *
    * @return <type>Dynamic</type>->Root_Xml_Element_Class<Widget>
    */
    #if haxe3 macro #else @:macro #end static public function buildFn (xmlFile:String) : Expr{
        if( !UIBuilder._initialized ) Err.trigger('Call UIBuilder.init()');

        var element = Xml.parse( File.getContent(xmlFile) ).firstElement();
        var cls : String = UIBuilder._imports.get(element.nodeName);

        var code : String = UIBuilder.construct(element);
        code += '\nreturn __ui__widget1;';
        code = 'function(__ui__arguments:Dynamic = null) : ' + cls + ' {' + code + '}';

        UIBuilder._saveCode(xmlFile, code);

        return UIBuilder._parse(xmlFile, code);
    }//function buildFn()


    /**
    * Register event type to declare event listeners in xml (attributes prefixed with `on-[shortcut]`).
    *
    * @param eventType - type of event we need to listen to. E.g. nme.events.MouseEvent.MOUSE_WHEEL
    * @param eventType - expected class of event. E.g. nme.events.MouseEvent.
    *
    * @throw <type>String</type> if this shortcut is already used
    */
    #if haxe3 macro #else @:macro #end static public function regEvent (shortcut:String, eventType:String, eventClass:String = 'nme.events.Event') : Expr{
        if( UIBuilder._events.exists(shortcut) ) Err.trigger('Event is already registered: ' + shortcut);
        UIBuilder._events.set(shortcut, [eventType, eventClass]);
        return Context.parse('true', Context.currentPos());
    }//function register()


    /**
    * Register class to use it in xml code.
    * For example 'com.pack.SomeClass' can be referenced in xml like this: $SomeClass
    *
    * @throw <type>String</type> if fullyQualifiedName is wrong (does not match `com.package.ClassName` notation)
    * @throw <type>String</type> if class is already registered. E.g. com.pack1.MyClass and org.pack2.MyClass
    * can not be registered simultaneously, because both will be shortened to $MyClass for usage in xml.
    * You still can register one of them and use another one by it's full classpath in xml
    */
    #if haxe3 macro #else @:macro #end static public function regClass (fullyQualifiedName:String) : Expr{
        var cls : String;

        var sc : EReg = ~/\.([a-z0-9_]+)$/i;
        if( sc.match(fullyQualifiedName) ){
            cls = sc.matched(1);
        }else{
            var sc : EReg = ~/^([a-z0-9_]+)$/i;
            if( sc.match(fullyQualifiedName) ){
                cls = sc.matched(1);
            }
        }

        if( cls != null ){
            if( UIBuilder._imports.exists(cls) ) Err.trigger('Class is already imported: ' + cls);
            UIBuilder._imports.set(cls, fullyQualifiedName);

        }else{
            Err.trigger('Wrong class name: ' + fullyQualifiedName);
        }

        return Context.parse('true', Context.currentPos());
    }//function regClass()


    /**
    * Register skin list. See samples/handlers_skinning for example skins.xml
    * @throw <type>String</type> if UIBuilder.init() was not called before
    * @throw <type>String</type> if one of tag names in xml does not match ~/^([a-z0-9_]+):([a-z0-9_]+)$/i
    * @throw <type>String</type> if class specified for skin system is not registered with .regClass
    */
    #if haxe3 macro #else @:macro #end static public function regSkins(xmlFile:String) : Expr {
        if( !UIBuilder._initialized ) Err.trigger('Call UIBuilder.init() first');

        var element = Xml.parse( File.getContent(xmlFile) ).firstElement();

        var code   : String = '';
        var erSkin : EReg = ~/^([a-z0-9_]+):([a-z0-9_]+)$/i;
        var local  : String = '';
        //process every skin
        for(node in element.elements()){
            if( !erSkin.match(node.nodeName) ) Err.trigger('Wrong skin format: ' + node.nodeName);

            var name : String = erSkin.matched(1);
            var cls  : String = erSkin.matched(2);

            if( !UIBuilder._imports.exists(cls) ) Err.trigger('Class is not imported: ' + cls);
            cls = UIBuilder._imports.get(cls);

            local = '\nvar skin = new ' +  cls + '();';

            //apply xml attributes to skin
            local += UIBuilder.attr2Haxe(node, 'skin');

            code += '\nru.stablex.ui.UIBuilder.skins.set("' + name + '", function():ru.stablex.ui.skins.Skin{' + local + '\nreturn skin;\n});';
        }//for(nodes)

        code = '(function(){' + code + '})()';

        UIBuilder._saveCode(xmlFile, code);

        return UIBuilder._parse(xmlFile, code);
    }//function regSkins()


#if !macro

    #if RTXML

    //parsed xml cache
    static private var _xmlCache : Hash<XmlCache> = new Hash();


    /**
    * Parse xml and cache result under specified name
    *
    */
    static public function parse (name:String, xml:String) : Void {

    }//function parse()

    #end


    /**
    * Creates unique id for widgets
    * @private
    */
    static public inline function createId() : String {
        return '__widget__' + Std.string( UIBuilder._nextId ++ );
    }//function createId()


    /**
    * Creates widgets at runtime.
    * You can add children like nested tags in xml by setting `properties.children` variable, wich
    * must be of <type>Array</type>&lt;<type>ru.stablex.ui.widgets.Widget</type>&gt;
    *
    * @param cls - create widget of this class;
    * @param properties - read description of .apply() method below.
    *
    * @throw <type>Dynamic</type> if corresponding properties of `cls` and `properties` have different types
    * @throw <type>String</type> if `cls` is not of <type>Class</type>&lt;<type>ru.stblex.ui.widgets.Widget</type>&gt;
    */
    static public function create<T>(cls:Class<T>, properties:Dynamic = null) : Null<T>{
        //create widget instance
        var obj : Widget = cast Type.createInstance(cls, []);

        if( obj == null ){
            Err.trigger('Wrong class provided for UIBuilder.create(). Must be Widget or extended Widget');
        }

        //apply defaults  {
            obj.defaults = Reflect.field(properties, 'defaults');
            if( obj.defaults == null ) obj.defaults = 'Default';
            UIBuilder.applyDefaults(obj);
        //}

        //if children are provided{
            var children : Array<Dynamic> = Reflect.field(properties, 'children');
            if( children != null ){
                Reflect.deleteField(properties, 'children');
            }
        //}

        //apply provided properties
        if( properties != null ){
            UIBuilder.apply(obj, properties);
        }

        obj._onInitialize();

        //add children
        if( children != null ){
            for(i in 0...children.length){
                if( Std.is(children[i], Widget) ){
                    obj.addChild(children[i]);
                }
            }
        }

        obj._onCreate();

        return cast obj;
    }//function create ()


    /**
    * Apply properties to object.
    * e. g. propList = {
    *                       prop1: -2,
    *                       prop2: true,
    *                       prop3: {
    *                           nested1: 'val1',
    *                           nested2: null,
    *                       },
    *                   }
    * than after calling UIBuilder.apply(someObj, propList) we will get following:
    *       someObj.prop1 == -2
    *       someObj.prop2 == true
    *       someObj.prop3.nested1 == 'val1'
    *       someObj.prop3.nested2 == null
    * Note: non-scalar object properties must not be null, otherwise you'll get an exception
    * "Can't set property of Null"
    *
    * @throw <type>Dynamic</type> if corresponding scalar properties of `obj` and `properties` have different types
    */
    static public function apply(obj:Dynamic, properties:Dynamic) : Void {
        for(property in Reflect.fields(properties)){

            //go deeper for nested properties
            if( Type.typeof(Reflect.field(properties, property)) == TObject ){
                UIBuilder.apply(Reflect.field(obj, property), Reflect.field(properties, property));

            //set scalar property
            }else{
                Reflect.setProperty(obj, property, Reflect.field(properties, property));
            }

        }//for(properties)
    }//function apply()


    /**
    * Apply defaults specified by obj.defaults
    *
    */
    static inline public function applyDefaults(obj:Widget) : Void {
        var clsName : String = Type.getClassName(Type.getClass(obj));
        var widgetDefaults : Hash<Widget->Void> = UIBuilder.defaults.get( clsName.substr(clsName.lastIndexOf('.', clsName.length - 1) + 1) );
        if( widgetDefaults != null ){
            var defs : Array<String> = obj.defaults.split(',');
            for(i in 0...defs.length){
                var defaultsFn : Widget->Void = widgetDefaults.get(defs[i]);
                if( defaultsFn != null ){
                    defaultsFn(obj);
                }
            }
        }
    }//function applyDefaults()



    /**
    * Get registered skin
    *
    */
    static public inline function skin (skinName:String) : Void->Skin {
        #if debug
            if( !UIBuilder.skins.exists(skinName) ){
                Err.trigger('Skin not found: ' + skinName);
            }
        #end
        return UIBuilder.skins.get(skinName);
    }//function skin()


    /**
    * Get widget object by its id
    *
    */
    static public inline function get(id:String) : Widget {
        return UIBuilder._objects.get(id);
    }//function get()


    /**
    * Return widget as instance of specified class. If widget is not of that class, returns null
    *
    */
    static public inline function getAs<T> (id:String, cls:Class<T>) : Null<T> {
        var w : Widget = UIBuilder.get(id);
        return ( Std.is(w, cls) ? cast w : null );
    }//function getAs<T>()


    /**
    * Associate widget with its id, so it can be acquired by UIBuilder.get()
    * @private
    */
    static public inline function save (obj:Widget) : Void{
        if( UIBuilder._objects.exists(obj.id) ){
            Err.trigger('Widget id "' + obj.id + '" is already used');
        }else{
            UIBuilder._objects.set(obj.id, obj);
        }
    }//function save()


    /**
    * "Forget" widget. Free its id for using in other widgets
    * @private
    */
    static public inline function forget (id:String) : Void{
        UIBuilder._objects.remove(id);
    }//function forget()


    /**
    * Add widget to `apply skin` queue. Skin applied once per frame
    * @private
    */
    static public inline function queueSkin (w:Widget) : Void {
        if( w.skin != null && !w._skinQueued ){
            UIBuilder._skinQueue.add(w);
            w._skinQueued = true;
        }
    }//function queueSkin()


    /**
    * Process skin UIBuilder._skinQueue
    * @private
    */
    static public function skinQueue (e:nme.events.Event = null) : Void {
        //if there is something to render in queue
        if( UIBuilder._skinQueue.length > 0 ){
            //get list we're going to process
            var lst : List<Widget> = UIBuilder._skinQueue;
            //create new list for next queue
            UIBuilder._skinQueue = new List();

            for(w in lst){
                w.applySkin();
                w._skinQueued = false;
            }

        }//if()
    }//function skinQueue()

#end
}//class UIBuilder