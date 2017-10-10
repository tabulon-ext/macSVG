//
//  TransformAttributeEditor.m
//  TransformAttributeEditor
//
//  Created by Douglas Ward on 1/26/12.
//  Copyright © 2016 ArkPhone LLC. All rights reserved.
//

//#define ENABLE
//#define SVG TRUE
//#define USE
//#define CG TRUE
//#define PLATFORM
//#define MAC TRUE

#import "TransformAttributeEditor.h"
#import <WebKit/WebKit.h>


#define transformToolModeNone 0
#define transformToolModeTranslate 1
#define transformToolModeScale 2
#define transformToolModeRotate 3
#define transformToolModeSkewX 4
#define transformToolModeSkewY 5
#define transformToolModeMatrix 6

#define PI 3.1415926535
#define radiansToDegrees 57.29577951308232		/* 180.0 / PI */
#define degreesToRadians 0.0174532925199433		/* PI / 180.0 */

#define svgNamespace @"http://www.w3.org/2000/svg"

#define TransformTableViewDataType @"NSMutableDictionary"


// mouseMode values
enum {
    MOUSE_UNSPECIFIED = 0,
    MOUSE_DISENGAGED = 1,
    MOUSE_DRAGGING = 2,
    MOUSE_HOVERING = 3
};

float getAngleABC( NSPoint a, NSPoint b, NSPoint c )
{
    NSPoint a1 = a;
    NSPoint c1 = c;
    
    a1.x -= b.x;
    c1.x -= b.x;
    
    a1.y -= b.y;
    c1.y -= b.y;

    float angba = atan2(a1.y, a1.x);
    float angbc = atan2(c1.y, c1.x);
    float rslt = angba - angbc;
    float rs = (rslt * 180.0f) / PI;
    rs = -rs; 

    return rs;
}

@implementation TransformAttributeEditor

//==================================================================================
//	init
//==================================================================================

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        mouseMode = MOUSE_DISENGAGED;
        clickPoint = NSMakePoint(0, 0);
        currentMousePoint = clickPoint;
        previousMousePoint = clickPoint;
        clickTarget = NULL;
        mouseMoveCount = 0;
        selectionHandleClicked = NO;
        handle_orientation = NULL;
        handleDegrees = 0.0f;
        elementRectAtMouseDown = NSZeroRect;
        settingToolButton = NO;

        self.transformsArray = [[NSMutableArray alloc] init];
        
        self.validElementsForTransformDictionary = @{@"rect": @"rect",
                @"circle": @"circle",
                @"ellipse": @"ellipse",
                @"text": @"text",
                @"image": @"image",
                @"line": @"line",
                @"polyline": @"polyline",
                @"polygon": @"polygon",
                @"path": @"path",
                @"use": @"use",
                @"g": @"g",
                @"foreignObject": @"foreignObject"};        
    }
    
    return self;
}

//==================================================================================
//	dealloc
//==================================================================================


- (void)dealloc 
{
    self.transformsArray = NULL;
    self.validElementsForTransformDictionary = NULL;
}

//==================================================================================
//	pluginName
//==================================================================================

- (NSString *)pluginName
{
    return @"Transform Attribute Editor";
}


//==================================================================================
//	floatFromString:
//==================================================================================

-(float) floatFromString:(NSString *)valueString
{
    float floatValue = 0;
    
    NSMutableString * trimmedString = [[NSMutableString alloc] init];
    
    NSUInteger inputLength = valueString.length;
    for (int i = 0; i < inputLength; i++)
    {
        unichar aChar = [valueString characterAtIndex:i];
        
        BOOL validChar = YES;
        
        if (aChar < '0') validChar = NO;
        if (aChar > '9') validChar = NO;
        if (aChar == '.') validChar = YES;
        if (aChar == '-') validChar = YES;
        
        if (validChar == NO) 
        {
            break;
        }
        
        NSString * charString = [[NSString alloc] initWithFormat:@"%C", aChar];
        
        [trimmedString appendString:charString];
    }
    
    floatValue = trimmedString.floatValue;
    
    return floatValue;
}

//==================================================================================
//	allocFloatString:
//==================================================================================

- (NSMutableString *)allocFloatString:(float)aFloat
{
    NSMutableString * aString = [[NSMutableString alloc] initWithFormat:@"%f", aFloat];

    BOOL continueTrim = YES;
    while (continueTrim == YES)
    {
        NSUInteger stringLength = aString.length;
        
        if (stringLength <= 1)
        {
            continueTrim = NO;
        }
        else
        {
            unichar lastChar = [aString characterAtIndex:(stringLength - 1)];
            
            if (lastChar == '0')
            {
                NSRange deleteRange = NSMakeRange(stringLength - 1, 1);
                [aString deleteCharactersInRange:deleteRange];
            }
            else if (lastChar == '.')
            {
                NSRange deleteRange = NSMakeRange(stringLength - 1, 1);
                [aString deleteCharactersInRange:deleteRange];
                continueTrim = NO;
            }
            else
            {
                continueTrim = NO;
            }
        }
    }
    return aString;
}

//==================================================================================
//	allocPxString:
//==================================================================================

- (NSMutableString *)allocPxString:(float)aFloat
{
    NSMutableString * aString = [[NSMutableString alloc] initWithFormat:@"%f", aFloat];

    BOOL continueTrim = YES;
    while (continueTrim == YES)
    {
        NSUInteger stringLength = aString.length;
        
        if (stringLength <= 1)
        {
            continueTrim = NO;
        }
        else
        {
            unichar lastChar = [aString characterAtIndex:(stringLength - 1)];
            
            if (lastChar == '0')
            {
                NSRange deleteRange = NSMakeRange(stringLength - 1, 1);
                [aString deleteCharactersInRange:deleteRange];
            }
            else if (lastChar == '.')
            {
                NSRange deleteRange = NSMakeRange(stringLength - 1, 1);
                [aString deleteCharactersInRange:deleteRange];
                continueTrim = NO;
            }
            else
            {
                continueTrim = NO;
            }
        }
    }
    
    [aString appendString:@"px"];
    
    return aString;
}

//==================================================================================
//	translatePoint:targetElement:
//==================================================================================

-(NSPoint) translatePoint:(NSPoint)aMousePoint targetElement:(DOMElement *)targetElement
{
    NSPoint resultPoint = aMousePoint;
    
    DOMDocument * domDocument = (self.svgWebView).mainFrame.DOMDocument;

    DOMNodeList * svgElementsList = [domDocument getElementsByTagNameNS:svgNamespace localName:@"svg"];
    if (svgElementsList.length > 0)
    {
        DOMNode * svgElementNode = [svgElementsList item:0];
        DOMElement * svgElement = (DOMElement *)svgElementNode;
        
        resultPoint = [self.webKitInterface transformPoint:aMousePoint fromElement:svgElement toElement:targetElement];
    }
    
    return resultPoint;
}

//==================================================================================
//	isEditorForElement:elementName:
//==================================================================================

// return label if this editor can edit specified element tag name
- (NSString *)isEditorForElement:(NSXMLElement *)aElement elementName:(NSString *)elementName
{
    NSString * result = NULL;

    return result;
}

//==================================================================================
//	isEditorForElement:elementName:attribute:
//==================================================================================

// return label if this editor can edit specified element and attribute
- (NSString *)isEditorForElement:(NSXMLElement *)aElement elementName:(NSString *)elementName attribute:(NSString *)attributeName
{   
    NSString * result = NULL;
    
    if ([attributeName isEqualToString:@"transform"] == YES) 
    {
        result = self.pluginName;
    }

    return result;
}

//==================================================================================
//	editorPriority:context:
//==================================================================================

- (NSInteger)editorPriority:(NSXMLElement *)targetElement context:(NSString *)context
{
    NSInteger result = 10;
    
    NSXMLNode * attributeNameNode = [targetElement attributeForName:@"transform"];
    if (attributeNameNode != NULL)
    {
        result = 30;
    }
    
    return result;
}

//==================================================================================
//	loadPluginViewInScrollView:
//==================================================================================

- (BOOL)loadPluginViewInScrollView:(NSScrollView *)scrollView
{
    return [super loadPluginViewInScrollView:scrollView];
}

//==================================================================================
//	syncDOMElementToXMLDocument:
//==================================================================================

-(void) syncDOMElementToXMLDocument
{
    NSMutableDictionary * newAttributesDictionary = [[NSMutableDictionary alloc] init];

    DOMNamedNodeMap * domAttributes = (self.pluginTargetDOMElement).attributes;
    NSInteger attCount = domAttributes.length;
    
    for (unsigned int a = 0; a < attCount; a++) 
    {
        DOMNode * attributes = [domAttributes item:a];
        NSString * attributeName = attributes.nodeName;
        NSString * attributeValue = attributes.nodeValue;
        
        NSRange xmlnsRange = [attributeName rangeOfString:@"xmlns"];
        if (xmlnsRange.location != NSNotFound)
        {
            NSLog(@"syncDOMElementToXMLDocument - xmlns namespace found as attribute");
        }
        
        if (attributeName.length > 0)
        {
            unichar firstChar = [attributeName characterAtIndex:0];
            if (firstChar != '_')
            {
                newAttributesDictionary[attributeName] = attributeValue;
            }
        }
    }
    
    [self.pluginTargetXMLElement setAttributesWithDictionary:newAttributesDictionary];
}

//==================================================================================
//	updateAttributeValue
//==================================================================================
/*
- (void)updateAttributeValue
{
    NSXMLNode * attributeNode = [pluginTargetXMLElement attributeForName:activeAttributeName];
    
    if (attributeNode != NULL)
    {
        NSString * transformString = @"translate(100 100)";
        [attributeNode setStringValue:transformString];
        
        [self updateDocumentViews];
    }
}
*/

//==================================================================================
//	setTransformAttribute
//==================================================================================

-(void) setTransformAttribute
{
    NSMutableString * newTransformString = [[NSMutableString alloc] init];
    
    NSUInteger functionCount = 0;
    
    for (NSMutableDictionary * transformDictionary in self.transformsArray)
    {
        if (functionCount > 0)
        {
            [newTransformString appendString:@" "];
        }
    
        NSString * functionString = transformDictionary[@"function"];
        NSString * xString = transformDictionary[@"x"];
        NSString * yString = transformDictionary[@"y"];
        NSString * degreesString = transformDictionary[@"degrees"];
        
        if ([functionString isEqualToString:@"translate"] == YES)
        {
            [newTransformString appendFormat:@"translate(%@ %@)", xString, yString];
        }
        else if ([functionString isEqualToString:@"rotate"] == YES)
        {
            [newTransformString appendFormat:@"rotate(%@", degreesString];
            
            if (xString != NULL)
            {
                if (xString.length > 0)
                {
                    if (yString != NULL)
                    {
                        if (yString.length > 0)
                        {
                            [newTransformString appendFormat:@" %@ %@", xString, yString];
                        }
                    }
                }
            }
            [newTransformString appendString:@")"];
        }
        else if ([functionString isEqualToString:@"scale"] == YES)
        {
            [newTransformString appendFormat:@"scale(%@", xString];
            
            if (yString != NULL)
            {
                if (yString.length > 0)
                {
                    [newTransformString appendFormat:@" %@", yString];
                }
            }
            [newTransformString appendString:@")"];
        }
        else if ([functionString isEqualToString:@"skewX"] == YES)
        {
            [newTransformString appendFormat:@"skewX(%@)", degreesString];
        }
        else if ([functionString isEqualToString:@"skewY"] == YES)
        {
            [newTransformString appendFormat:@"skewY(%@)", degreesString];
        }
        else if ([functionString isEqualToString:@"matrix"] == YES)
        {
            NSString * m1 = transformDictionary[@"m1"];
            NSString * m2 = transformDictionary[@"m2"];
            NSString * m3 = transformDictionary[@"m3"];
            NSString * m4 = transformDictionary[@"m4"];
            NSString * m5 = transformDictionary[@"m5"];
            NSString * m6 = transformDictionary[@"m6"];
            [newTransformString appendFormat:@"matrix(%@ %@ %@ %@ %@ %@)", 
                    m1, m2, m3, m4, m5, m6];
        }
        
        functionCount++;
    }
    
    [self.pluginTargetDOMElement setAttribute:@"transform" value:newTransformString];
    
    [self syncDOMElementToXMLDocument];

    [self.macSVGPluginCallbacks updateSelections]; // update selection rectangles and handles
    
    NSInteger selectedRow = transformsTableView.selectedRow;
    [transformsTableView setNeedsDisplayInRect:[transformsTableView 
            frameOfCellAtColumn:0 row:selectedRow]];
}

//==================================================================================
//	numberOfRowsInTableView
//==================================================================================

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return (self.transformsArray).count;
}

//==================================================================================
//	tableView:objectValueForTableColumn:rowIndex
//==================================================================================

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    id objectValue = NULL;
    NSDictionary * transformDictionary = (self.transformsArray)[rowIndex];
    
    if (transformDictionary != NULL)
    {
        NSString * transformFunction = transformDictionary[@"function"];
        
        NSString * transformValues = @"";
        
        if ([transformFunction isEqualToString:@"translate"] == YES) 
        {
            NSString * xString = transformDictionary[@"x"];
            NSString * yString = transformDictionary[@"y"];
            transformValues = [NSString stringWithFormat:@"%@ %@",
                    xString, yString];
        }
        else if ([transformFunction isEqualToString:@"scale"] == YES) 
        {
            NSString * xString = transformDictionary[@"x"];
            NSString * yString = transformDictionary[@"y"];
            if (yString == NULL)
            {
                transformValues = [NSString stringWithFormat:@"%@",
                        xString];
            }
            else
            {
                transformValues = [NSString stringWithFormat:@"%@ %@",
                        xString, yString];
            }
        }
        else if ([transformFunction isEqualToString:@"rotate"] == YES) 
        {
            NSString * degreesString = transformDictionary[@"degrees"];
            NSString * xString = transformDictionary[@"x"];
            NSString * yString = transformDictionary[@"y"];
            if (xString == NULL)
            {
                transformValues = [NSString stringWithFormat:@"%@",
                        degreesString];
            }
            else
            {
                transformValues = [NSString stringWithFormat:@"%@ %@ %@",
                        degreesString, xString, yString];
            }
        }
        else if ([transformFunction isEqualToString:@"skewX"] == YES) 
        {
            NSString * degreesString = transformDictionary[@"degrees"];
            transformValues = degreesString;
        }
        else if ([transformFunction isEqualToString:@"skewY"] == YES) 
        {
            NSString * degreesString = transformDictionary[@"degrees"];
            transformValues = degreesString;
        }
        else if ([transformFunction isEqualToString:@"matrix"] == YES)
        {
            NSString * m1String = transformDictionary[@"m1"];
            NSString * m2String = transformDictionary[@"m2"];
            NSString * m3String = transformDictionary[@"m3"];
            NSString * m4String = transformDictionary[@"m4"];
            NSString * m5String = transformDictionary[@"m5"];
            NSString * m6String = transformDictionary[@"m6"];
            
            if (m1String == NULL) m1String = @"0";
            if (m2String == NULL) m2String = @"0";
            if (m3String == NULL) m3String = @"0";
            if (m4String == NULL) m4String = @"0";
            if (m5String == NULL) m5String = @"0";
            if (m6String == NULL) m6String = @"0";
            
            transformValues = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", m1String, m2String, m3String, m4String, m5String ,m6String];
        }
        
        objectValue = [NSString stringWithFormat:@"%@(%@)", transformFunction, transformValues];
    } 
    
    return objectValue;
}


//==================================================================================
//	awakeFromNib
//==================================================================================

- (void)awakeFromNib 
{
    [super awakeFromNib];

    [transformsTableView registerForDraggedTypes:@[TransformTableViewDataType]];
    
    translateToolButton.image = NULL;
    scaleToolButton.image = NULL;
    rotateToolButton.image = NULL;
    skewXToolButton.image = NULL;
    skewYToolButton.image = NULL;
}

//==================================================================================
//	tableView:writeRowsWithIndexes:toPasteboard
//==================================================================================

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
    // Copy the row numbers to the pasteboard.
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];

    [pboard declareTypes:@[TransformTableViewDataType] owner:self];

    [pboard setData:data forType:TransformTableViewDataType];
    
    return YES;
}

//==================================================================================
//	tableView:acceptDrop:row:dropOperation
//==================================================================================

- (BOOL)tableView:(NSTableView*)tableView 
        acceptDrop:(id <NSDraggingInfo>)info 
        row:(NSInteger)row
        dropOperation:(NSTableViewDropOperation)operation
{
    //this is the code that handles dnd ordering - my table doesn't need to accept drops from outside! Hooray!
    NSPasteboard * pboard = [info draggingPasteboard];
    NSData * rowData = [pboard dataForType:TransformTableViewDataType];

    NSIndexSet * rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];

    NSInteger from = rowIndexes.firstIndex;

    NSMutableDictionary * traveller = (self.transformsArray)[from];
    
    NSInteger length = (self.transformsArray).count;
    //NSMutableArray * replacement = [NSMutableArray new];

    NSInteger i;
    for (i = 0; i <= length; i++)
    {
        if (i == row)
        {
            if (from > row)
            {
                [self.transformsArray insertObject:traveller atIndex:row];
                [self.transformsArray removeObjectAtIndex:(from + 1)];
            }
            else
            {
                [self.transformsArray insertObject:traveller atIndex:row];
                [self.transformsArray removeObjectAtIndex:from];
            }
        }
    }
    
    [transformsTableView reloadData];
    
    [self setTransformAttribute];
    
    return YES;
}


//==================================================================================
//	tableView:validateDrop:proposedRow:proposedDropOperation:
//==================================================================================

- (NSDragOperation)tableView:(NSTableView*)tableView 
        validateDrop:(id <NSDraggingInfo>)info 
        proposedRow:(NSInteger)row
        proposedDropOperation:(NSTableViewDropOperation)operation
{
    return NSDragOperationEvery;
}

//==================================================================================
//	tableView:writeRows:toPasteboard:
//==================================================================================
/*
- (BOOL)tableView:(NSTableView *)tableView 
        writeRows:(NSArray*)rows
        toPasteboard:(NSPasteboard*)pboard
{
    return YES;
}
*/
//==================================================================================
//	beginTranslateTransform
//==================================================================================

-(void) beginTranslateTransform
{
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    BOOL makeNewTranslateItem = NO;
    
    NSString * xString = @"0";
    NSString * yString = @"0";
    
    if (selectedRow == -1)
    {
        makeNewTranslateItem = YES;
    }
    else
    {
        NSMutableDictionary * selectedTransformDictionary =
                (self.transformsArray)[selectedRow];
        
        NSString * selectedFunction = selectedTransformDictionary[@"function"];
        
        if ([selectedFunction isEqualToString:@"translate"] == YES)
        {
            xString = selectedTransformDictionary[@"x"];
            yString = selectedTransformDictionary[@"y"];
        }
        else
        {
            // current selection is not a translate, so append a new translate function
            makeNewTranslateItem = YES;
        }
    }
    
    if (makeNewTranslateItem == YES)
    {
        // no row selected, create a new item for the command
        NSMutableDictionary * newTransformDictionary =   [[NSMutableDictionary alloc] init];
        
        newTransformDictionary[@"function"] = @"translate";
        newTransformDictionary[@"x"] = xString;
        newTransformDictionary[@"y"] = yString;
        
        selectedRow++;
        
        //[transformsArray addObject:newTransformDictionary];
        [self.transformsArray insertObject:newTransformDictionary atIndex:selectedRow];
        
        [transformsTableView reloadData];
        
        //selectedRow = [transformsArray count] - 1;
        
        NSIndexSet * rowIndex = [[NSIndexSet alloc] initWithIndex:selectedRow];
        
        [transformsTableView selectRowIndexes:rowIndex byExtendingSelection:NO];
    }
    
    [label1TextField setHidden:NO];
    label1TextField.stringValue = @"x:";

    [value1TextField setHidden:NO];
    value1TextField.stringValue = xString;
    
    [label2TextField setHidden:NO];
    label2TextField.stringValue = @"y:";

    [value2TextField setHidden:NO];
    value2TextField.stringValue = yString;
    
    [label3TextField setHidden:YES];
    label3TextField.stringValue = @"";

    [value3TextField setHidden:YES];
    value3TextField.stringValue = @"";

    [label4TextField setHidden:YES];
    label4TextField.stringValue = @"";

    [value4TextField setHidden:YES];
    value4TextField.stringValue = @"";

    [label5TextField setHidden:YES];
    label5TextField.stringValue = @"";

    [value5TextField setHidden:YES];
    value5TextField.stringValue = @"";

    [label6TextField setHidden:YES];
    label6TextField.stringValue = @"";

    [value6TextField setHidden:YES];
    value6TextField.stringValue = @"";
    
    functionButton.hidden = YES;
    
    transformsTableView.nextKeyView = value1TextField;
    value1TextField.nextKeyView = value2TextField;
    value2TextField.nextKeyView = transformsTableView;
    [value3TextField setNextKeyView:NULL];
    
    [self setTransformAttribute];
}

//==================================================================================
//	handleMouseMoveEventForTranslate:
//==================================================================================

-(void) handleMouseMoveEventForTranslate:(DOMEvent *)event
{
    //NSLog(@"handleMouseMoveEventForTranslate");

    NSInteger selectedRow = transformsTableView.selectedRow;
    
    if (selectedRow != -1)
    {
        NSMutableDictionary * translateDictionary = (self.transformsArray)[selectedRow];
            
        NSString * previousTranslateXString = translateDictionary[@"x"];
        NSString * previousTranslateYString = translateDictionary[@"y"];
        
        float previousTranslateX = previousTranslateXString.floatValue;
        float previousTranslateY = previousTranslateYString.floatValue;
        
        float deltaX = currentMousePoint.x - previousMousePoint.x;
        float deltaY = currentMousePoint.y - previousMousePoint.y;

        NSPoint deltaPoint = NSMakePoint(deltaX, deltaY);
        deltaPoint = [self translatePoint:deltaPoint targetElement:self.pluginTargetDOMElement.parentElement];

        if (mouseMoveCount == 1)
        {
            [self.macSVGPluginCallbacks pushUndoRedoDocumentChanges];
        }

        // update the positions of the selected SVG elements
        DOMElement * aSvgElement = self.pluginTargetDOMElement;

        if (mouseMoveCount == 1)
        {
            [self.macSVGPluginCallbacks pushUndoRedoDocumentChanges];
        }
        
        NSString * elementName = aSvgElement.nodeName;
        if ((self.validElementsForTransformDictionary)[elementName] != NULL)
        {
            NSString * transformAttributeString = [aSvgElement getAttribute:@"transform"];
            
            if ((transformAttributeString != NULL))
            {
                float newX = previousTranslateX + deltaPoint.x;
                float newY = previousTranslateY + deltaPoint.y;
            
                NSString * newXString = [self allocFloatString:newX];
                NSString * newYString = [self allocFloatString:newY];
                
                translateDictionary[@"x"] = newXString;
                translateDictionary[@"y"] = newYString;
                
                value1TextField.stringValue = newXString;
                value2TextField.stringValue = newYString;
            }
            
            [self setTransformAttribute];
        }
    }
}    

//==================================================================================
//	beginScaleTransform
//==================================================================================

-(void) beginScaleTransform
{
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    BOOL makeNewScaleItem = NO;

    NSString * xString = @"1";
    NSString * yString = @"1";
    
    if (selectedRow == -1)
    {
        makeNewScaleItem = YES;
    }
    else
    {
        NSMutableDictionary * selectedTransformDictionary =
                (self.transformsArray)[selectedRow];
        
        NSString * selectedFunction = selectedTransformDictionary[@"function"];
        
        if ([selectedFunction isEqualToString:@"scale"] == YES)
        {
            xString = selectedTransformDictionary[@"x"];
            yString = selectedTransformDictionary[@"y"];
        }
        else
        {
            // current selection is not a scale, so append a new scale function
            makeNewScaleItem = YES;
        }
    }
    
    if (makeNewScaleItem == YES)
    {
        // no row selected, create a new item for the command
        NSMutableDictionary * newTransformDictionary =   [[NSMutableDictionary alloc] init];
        
        newTransformDictionary[@"function"] = @"scale";
        newTransformDictionary[@"x"] = xString;
        newTransformDictionary[@"y"] = yString;
        
        selectedRow++;
        
        //[transformsArray addObject:newTransformDictionary];
        [self.transformsArray insertObject:newTransformDictionary atIndex:selectedRow];

        [transformsTableView reloadData];
        
        //selectedRow = [transformsArray count] - 1;
        
        NSIndexSet * rowIndex = [[NSIndexSet alloc] initWithIndex:selectedRow];
        
        [transformsTableView selectRowIndexes:rowIndex byExtendingSelection:NO];
    }

    if ([xString isEqualToString:@"inf"] == YES)
    {
        yString = @"1";
    }
    
    if ([yString isEqualToString:@"inf"] == YES)
    {
        yString = @"1";
    }
    
    [label1TextField setHidden:NO];
    label1TextField.stringValue = @"x";

    [value1TextField setHidden:NO];
    value1TextField.stringValue = xString;
    
    [label2TextField setHidden:NO];
    label2TextField.stringValue = @"y";

    [value2TextField setHidden:NO];
    value2TextField.stringValue = yString;
    
    [label3TextField setHidden:YES];
    label3TextField.stringValue = @"";

    [value3TextField setHidden:YES];
    value3TextField.stringValue = @"";

    [value4TextField setHidden:YES];
    value4TextField.stringValue = @"";

    [value5TextField setHidden:YES];
    value5TextField.stringValue = @"";

    [value6TextField setHidden:YES];
    value6TextField.stringValue = @"";

    functionButton.hidden = YES;

    transformsTableView.nextKeyView = value1TextField;
    value1TextField.nextKeyView = value2TextField;
    value2TextField.nextKeyView = transformsTableView;
    [value3TextField setNextKeyView:NULL];

    [self setTransformAttribute];
}

//==================================================================================
//	handleMouseMoveEventForScale:
//==================================================================================

-(void) handleMouseMoveEventForScale:(DOMEvent *)event
{
    //NSLog(@"handleMouseMoveEventForScale");

    NSString * elementTagName = (self.pluginTargetDOMElement).tagName;
    if ((self.validElementsForTransformDictionary)[elementTagName] != NULL)
    {
        NSInteger selectedRow = transformsTableView.selectedRow;
        
        if (selectedRow != -1)
        {
            NSMutableDictionary * scaleDictionary = (self.transformsArray)[selectedRow];

            NSString * scaleXString = scaleDictionary[@"x"];
            NSString * scaleYString = scaleDictionary[@"y"];

            float scaleX = scaleXString.floatValue;
            float scaleY = scaleYString.floatValue;

            NSRect offsetRect = NSMakeRect(self.pluginTargetDOMElement.offsetLeft, self.pluginTargetDOMElement.offsetTop,
                    self.pluginTargetDOMElement.offsetWidth, self.pluginTargetDOMElement.offsetHeight);

            if (NSIsEmptyRect(offsetRect) == NO)
            {
                NSLog(@"offsetRect found %f, %f, %f, %f",
                        offsetRect.origin.x, offsetRect.origin.y,
                        offsetRect.size.width, offsetRect.size.height);
            }
            
            NSRect clientRect = NSMakeRect(self.pluginTargetDOMElement.clientLeft, self.pluginTargetDOMElement.clientTop,
                    self.pluginTargetDOMElement.clientWidth, self.pluginTargetDOMElement.clientHeight);
            if (NSIsEmptyRect(clientRect) == NO)
            {
                NSLog(@"clientRect found %f, %f, %f, %f",
                        clientRect.origin.x, clientRect.origin.y,
                        clientRect.size.width, clientRect.size.height);
            }



            
            NSRect scalingRect = NSZeroRect;
            
            BOOL useXY = NO;
            BOOL useCxCyR = NO;
            BOOL useCxCyRxRy = NO;
            BOOL useBoundingBox = NO;
            
            if ([elementTagName isEqualToString:@"rect"] == YES) useXY = YES;
            
            if ([elementTagName isEqualToString:@"circle"] == YES) useCxCyR = YES;
            if ([elementTagName isEqualToString:@"ellipse"] == YES) useCxCyRxRy = YES;
            
            if ([elementTagName isEqualToString:@"line"] == YES) useBoundingBox = YES;
            if ([elementTagName isEqualToString:@"polyline"] == YES) useBoundingBox = YES;
            if ([elementTagName isEqualToString:@"polygon"] == YES) useBoundingBox = YES;
            if ([elementTagName isEqualToString:@"path"] == YES) useBoundingBox = YES;
            if ([elementTagName isEqualToString:@"text"] == YES) useBoundingBox = YES;
            
            if ([elementTagName isEqualToString:@"g"] == YES) useBoundingBox = YES;
            if ([elementTagName isEqualToString:@"foreignObject"] == YES) useBoundingBox = YES;
            if ([elementTagName isEqualToString:@"use"] == YES) useBoundingBox = YES;
            
            if (useXY == YES)
            {
                NSString * xAttributeString = [self.pluginTargetDOMElement getAttribute:@"x"];
                NSString * yAttributeString = [self.pluginTargetDOMElement getAttribute:@"y"];
                NSString * widthAttributeString = [self.pluginTargetDOMElement getAttribute:@"width"];
                NSString * heightAttributeString = [self.pluginTargetDOMElement getAttribute:@"height"];
                if ((xAttributeString.length > 0) && (yAttributeString.length > 0) &&
                        (widthAttributeString.length > 0) && (heightAttributeString.length > 0))
                {
                    float xAttribute = xAttributeString.floatValue;
                    float yAttribute = yAttributeString.floatValue;
                    float widthAttribute = widthAttributeString.floatValue;
                    float heightAttribute = heightAttributeString.floatValue;
                    
                    scalingRect = NSMakeRect(xAttribute, yAttribute, widthAttribute, heightAttribute);
                }
            }
            
            if (useCxCyR == YES)
            {
                NSString * cxAttributeString = [self.pluginTargetDOMElement getAttribute:@"cx"];
                NSString * cyAttributeString = [self.pluginTargetDOMElement getAttribute:@"cy"];
                NSString * rAttributeString = [self.pluginTargetDOMElement getAttribute:@"r"];
                if ((cxAttributeString.length > 0) && (cyAttributeString.length > 0) &&
                        (rAttributeString.length > 0))
                {
                    float cxAttribute = cxAttributeString.floatValue;
                    float cyAttribute = cyAttributeString.floatValue;
                    float rAttribute = rAttributeString.floatValue;
                    
                    scalingRect = NSMakeRect(cxAttribute, cyAttribute, rAttribute * 2.0f, rAttribute * 2.0f);
                }
            }
            
            if (useCxCyRxRy == YES)
            {
                NSString * cxAttributeString = [self.pluginTargetDOMElement getAttribute:@"cx"];
                NSString * cyAttributeString = [self.pluginTargetDOMElement getAttribute:@"cy"];
                NSString * rxAttributeString = [self.pluginTargetDOMElement getAttribute:@"rx"];
                NSString * ryAttributeString = [self.pluginTargetDOMElement getAttribute:@"ry"];
                if ((cxAttributeString.length > 0) && (cyAttributeString.length > 0) &&
                        (rxAttributeString.length > 0) && (ryAttributeString.length > 0))
                {
                    float cxAttribute = cxAttributeString.floatValue;
                    float cyAttribute = cyAttributeString.floatValue;
                    float rxAttribute = rxAttributeString.floatValue;
                    float ryAttribute = ryAttributeString.floatValue;
                    
                    scalingRect = NSMakeRect(cxAttribute, cyAttribute, rxAttribute * 2.0f, ryAttribute * 2.0f);
                }
            }
            
            if (useBoundingBox == YES)
            {
                //NSRect boundingBoxRect = [webKitInterface bBoxForDOMElement:pluginTargetDOMElement globalContext:globalContext];
                NSRect boundingBoxRect = [self.webKitInterface bBoxForDOMElement:self.pluginTargetDOMElement];

                scalingRect = boundingBoxRect;
            }

            DOMDocument * domDocument = (self.svgWebView).mainFrame.DOMDocument;

            NSRect pageRect;
            DOMNodeList * svgElementsList = [domDocument getElementsByTagNameNS:svgNamespace localName:@"svg"];
            DOMElement * svgRootElement = NULL;
            if (svgElementsList.length > 0)
            {
                DOMNode * svgElementNode = [svgElementsList item:0];
                svgRootElement = (DOMElement *)svgElementNode;
            
                pageRect = [self.webKitInterface pageRectForElement:self.pluginTargetDOMElement svgRootElement:svgRootElement];
            }
            else
            {
                NSLog(@"svg root element not found");
            }
            
            NSPoint translatedMousePoint = [self translatePoint:currentMousePoint targetElement:self.pluginTargetDOMElement.parentElement];

            if ([handle_orientation isEqualToString:@"top"] == YES)
            {
                scaleY = ((elementRectAtMouseDown.origin.y + elementRectAtMouseDown.size.height) - translatedMousePoint.y) /
                        scalingRect.size.height;
            }
            else if ([handle_orientation isEqualToString:@"left"] == YES)
            {
                scaleX = ((elementRectAtMouseDown.origin.x + elementRectAtMouseDown.size.width) - translatedMousePoint.x) /
                        scalingRect.size.width;
            }
            else if ([handle_orientation isEqualToString:@"bottom"] == YES)
            {
            
                scaleY = (translatedMousePoint.y - elementRectAtMouseDown.origin.y) /
                        scalingRect.size.height;
            }
            else if ([handle_orientation isEqualToString:@"right"] == YES)
            {
                scaleX = (translatedMousePoint.x - elementRectAtMouseDown.origin.x) /
                        scalingRect.size.width;
            }
            else if ([handle_orientation isEqualToString:@"topLeft"] == YES)
            {
                scaleX = ((elementRectAtMouseDown.origin.x + elementRectAtMouseDown.size.width) - translatedMousePoint.x) /
                        scalingRect.size.width;
                scaleY = ((elementRectAtMouseDown.origin.y + elementRectAtMouseDown.size.height) - translatedMousePoint.y) /
                        scalingRect.size.height;
            }
            else if ([handle_orientation isEqualToString:@"topRight"] == YES)
            {
                scaleX = (translatedMousePoint.x - elementRectAtMouseDown.origin.x) /
                        scalingRect.size.width;
                scaleY = ((elementRectAtMouseDown.origin.y + elementRectAtMouseDown.size.height) - translatedMousePoint.y) /
                        scalingRect.size.height;
            }
            else if ([handle_orientation isEqualToString:@"bottomLeft"] == YES)
            {
                scaleX = ((elementRectAtMouseDown.origin.x + elementRectAtMouseDown.size.width) - translatedMousePoint.x) /
                        scalingRect.size.width;
                scaleY = (translatedMousePoint.y - elementRectAtMouseDown.origin.y) /
                        scalingRect.size.height;
            }
            else if ([handle_orientation isEqualToString:@"bottomRight"] == YES)
            {
                scaleX = (translatedMousePoint.x - elementRectAtMouseDown.origin.x) /
                        scalingRect.size.width;
                scaleY = (translatedMousePoint.y - elementRectAtMouseDown.origin.y) /
                        scalingRect.size.height;
            }

            // update the positions of the selected SVG elements
            if (mouseMoveCount == 1)
            {
                [self.macSVGPluginCallbacks pushUndoRedoDocumentChanges];
            }

            NSString * transformAttributeString = [self.pluginTargetDOMElement getAttribute:@"transform"];
            
            if ((transformAttributeString != NULL))
            {
                NSString * newXString = [self allocFloatString:scaleX];
                NSString * newYString = [self allocFloatString:scaleY];
                
                scaleDictionary[@"x"] = newXString;
                scaleDictionary[@"y"] = newYString;
                
                value1TextField.stringValue = newXString;
                value2TextField.stringValue = newYString;
            }
            
            [self setTransformAttribute];
        }
    }
}    

//==================================================================================
//	beginRotateTransform
//==================================================================================

-(void) beginRotateTransform
{
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    BOOL makeNewRotateItem = NO;

    NSMutableDictionary * rotateTransformDictionary = NULL;

    NSString * degreesString = @"0";
    NSString * xString = @"0";
    NSString * yString = @"0";
    
    if (selectedRow == -1)
    {
        makeNewRotateItem = YES;
    }
    else
    {
        rotateTransformDictionary =
                (self.transformsArray)[selectedRow];
        
        NSString * selectedFunction = rotateTransformDictionary[@"function"];
        
        if ([selectedFunction isEqualToString:@"rotate"] == YES)
        {
            degreesString = rotateTransformDictionary[@"degrees"];
            xString = rotateTransformDictionary[@"x"];
            yString = rotateTransformDictionary[@"y"];
            
            if (xString == NULL)
            {
                xString = @"0";
            }
            
            if (yString == NULL)
            {
                yString = @"0";
            }
        }
        else
        {
            // current selection is not a rotate, so append a new rotate function
            makeNewRotateItem = YES;
        }
    }
    
    if (makeNewRotateItem == YES)
    {
        // no row selected, create a new item for the command
        rotateTransformDictionary =   [[NSMutableDictionary alloc] init];
        
        NSRect boundingBox = [self.webKitInterface bBoxForDOMElement:self.pluginTargetDOMElement];
        float bboxX = boundingBox.origin.x;
        float bboxY = boundingBox.origin.y;
        float bboxWidth = boundingBox.size.width;
        float bboxHeight = boundingBox.size.height;
        
        
        float bboxXMax = bboxX + bboxWidth;
        float bboxYMax = bboxY + bboxHeight;
        
        float bboxXCenter = (bboxX + bboxXMax) * 0.5f;
        float bboxYCenter = (bboxY + bboxYMax) * 0.5f;
        
        NSString * centerXString = [self allocFloatString:bboxXCenter];
        NSString * centerYString = [self allocFloatString:bboxYCenter];
        
        rotateTransformDictionary[@"function"] = @"rotate";
        rotateTransformDictionary[@"degrees"] = degreesString;
        rotateTransformDictionary[@"x"] = centerXString;
        rotateTransformDictionary[@"y"] = centerYString;
        
        xString = centerXString;
        yString = centerYString;
        
        selectedRow++;
        
        [self.transformsArray insertObject:rotateTransformDictionary atIndex:selectedRow];

        [transformsTableView reloadData];
        
        NSIndexSet * rowIndex = [[NSIndexSet alloc] initWithIndex:selectedRow];
        
        [transformsTableView selectRowIndexes:rowIndex byExtendingSelection:NO];
    }
    
    [label1TextField setHidden:NO];
    label1TextField.stringValue = @"degrees";

    [value1TextField setHidden:NO];
    value1TextField.stringValue = degreesString;
    
    [label2TextField setHidden:NO];
    label2TextField.stringValue = @"x";

    [value2TextField setHidden:NO];
    value2TextField.stringValue = xString;
    
    [label3TextField setHidden:NO];
    label3TextField.stringValue = @"y";

    [value3TextField setHidden:NO];
    value3TextField.stringValue = yString;

    [value4TextField setHidden:YES];
    value4TextField.stringValue = @"";

    [value5TextField setHidden:YES];
    value5TextField.stringValue = @"";

    [value6TextField setHidden:YES];
    value6TextField.stringValue = @"";

    functionButton.hidden = NO;
    functionButton.title = @"Set Rotation at Center";

    transformsTableView.nextKeyView = value1TextField;
    value1TextField.nextKeyView = value2TextField;
    value2TextField.nextKeyView = value3TextField;
    value3TextField.nextKeyView = transformsTableView;

    [self setTransformAttribute];

    float currentDegrees = 0.0f;
    NSString * degreesAttribute = rotateTransformDictionary[@"degrees"];
    if (degreesAttribute != NULL)
    {
        if (degreesAttribute.length > 0)
        {
            currentDegrees = degreesAttribute.floatValue;
        }
    }

    NSRect boundingBox = [self.webKitInterface bBoxForDOMElement:self.pluginTargetDOMElement];
    float bboxX = boundingBox.origin.x;
    float bboxY = boundingBox.origin.y;
    float bboxWidth = boundingBox.size.width;
    float bboxHeight = boundingBox.size.height;
    
    float bboxXMax = bboxX + bboxWidth;
    float bboxYMax = bboxY + bboxHeight;
    
    float bboxXCenter = (bboxX + bboxXMax) / 2.0f;
    float bboxYCenter = (bboxY + bboxYMax) / 2.0f;
    
    NSPoint pointA = NSMakePoint(bboxXCenter, 0);
    pointA.x *= currentScale;

    NSPoint pointB = NSMakePoint(bboxXCenter, bboxYCenter);
    pointB.x *= currentScale;
    pointB.y *= currentScale;

    NSPoint pointC = currentMousePoint;
    
    handleDegrees = getAngleABC(pointA, pointB, pointC) - currentDegrees;
}


//==================================================================================
//	handleMouseMoveEventForRotate:
//==================================================================================

-(void) handleMouseMoveEventForRotate:(DOMEvent *)event
{
    //NSLog(@"handleMouseMoveEventForRotate");

    NSInteger selectedRow = transformsTableView.selectedRow;
    
    if (selectedRow != -1)
    {
        NSMutableDictionary * rotateDictionary = (self.transformsArray)[selectedRow];
                    
        NSRect boundingBox = [self.webKitInterface bBoxForDOMElement:self.pluginTargetDOMElement];

        //NSLog(@"rotate bBox1 = %f, %f, %f, %f", boundingBox.origin.x, boundingBox.origin.y,
        //        boundingBox.size.width, boundingBox.size.height);

        DOMDocument * domDocument = (self.svgWebView).mainFrame.DOMDocument;
        DOMNodeList * svgElementsList = [domDocument getElementsByTagNameNS:svgNamespace localName:@"svg"];
        DOMElement * svgRootElement = NULL;
        if (svgElementsList.length > 0)
        {
            DOMNode * svgElementNode = [svgElementsList item:0];
            svgRootElement = (DOMElement *)svgElementNode;
            boundingBox = [self.webKitInterface pageRectForElement:self.pluginTargetDOMElement svgRootElement:svgRootElement];

            //NSLog(@"rotate bBox2 = %f, %f, %f, %f", boundingBox.origin.x, boundingBox.origin.y,
            //        boundingBox.size.width, boundingBox.size.height);
        }
        
        float bboxX = boundingBox.origin.x;
        float bboxY = boundingBox.origin.y;
        float bboxWidth = boundingBox.size.width;
        float bboxHeight = boundingBox.size.height;
        
        float bboxXMax = bboxX + bboxWidth;
        float bboxYMax = bboxY + bboxHeight;
        
        float bboxXCenter = (bboxX + bboxXMax) / 2.0f;
        float bboxYCenter = (bboxY + bboxYMax) / 2.0f;

        NSPoint pointA = NSMakePoint(bboxXCenter, 0);
        pointA.x *= currentScale;
        
        NSPoint pointB = NSMakePoint(bboxXCenter, bboxYCenter);
        pointB.x *= currentScale;
        pointB.y *= currentScale;
        
        NSPoint pointC = currentMousePoint;
        pointC.x *= currentScale;
        pointC.y *= currentScale;
        
        //NSLog(@"rotate a=%f,%f b=%f,%f c=%f,%f", pointA.x, pointA.y, pointB.x, pointB.y, pointC.x, pointC.y);

        float newHandleDegrees = getAngleABC(pointA, pointB, pointC);
        
        float rotateDegrees = newHandleDegrees - handleDegrees;

        if (mouseMoveCount == 1)
        {
            [self.macSVGPluginCallbacks pushUndoRedoDocumentChanges];
        }

        // update the positions of the selected SVG elements
        DOMElement * aSvgElement = self.pluginTargetDOMElement;

        NSString * elementName = aSvgElement.nodeName;
        if ((self.validElementsForTransformDictionary)[elementName] != NULL)
        {
            NSString * transformAttributeString = [aSvgElement getAttribute:@"transform"];
            
            if ((transformAttributeString != NULL))
            {
                NSString * newDegreeString = [self allocFloatString:rotateDegrees];
                
                rotateDictionary[@"degrees"] = newDegreeString;
                
                value1TextField.stringValue = newDegreeString;
            }
            
            [self setTransformAttribute];
        }
    }
}    

//==================================================================================
//	beginSkewXTransform
//==================================================================================

-(void) beginSkewXTransform
{
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    BOOL makeNewSkewXItem = NO;

    NSMutableDictionary * skewXTransformDictionary = NULL;

    NSString * degreesString = @"0";
    
    if (selectedRow == -1)
    {
        makeNewSkewXItem = YES;
    }
    else
    {
        skewXTransformDictionary =
                (self.transformsArray)[selectedRow];
        
        NSString * selectedFunction = skewXTransformDictionary[@"function"];
        
        if ([selectedFunction isEqualToString:@"skewX"] == YES)
        {
            degreesString = skewXTransformDictionary[@"degrees"];
        }
        else
        {
            // current selection is not a translate, so append a new translate function
            makeNewSkewXItem = YES;
        }
    }
    
    if (makeNewSkewXItem == YES)
    {
        // no row selected, create a new item for the command
        skewXTransformDictionary =   [[NSMutableDictionary alloc] init];
        
        skewXTransformDictionary[@"function"] = @"skewX";
        skewXTransformDictionary[@"degrees"] = degreesString;
        
        selectedRow++;
        
        //[transformsArray addObject:skewXTransformDictionary];
        [self.transformsArray insertObject:skewXTransformDictionary atIndex:selectedRow];

        [transformsTableView reloadData];
        
        //selectedRow = [transformsArray count] - 1;
        
        NSIndexSet * rowIndex = [[NSIndexSet alloc] initWithIndex:selectedRow];
        
        [transformsTableView selectRowIndexes:rowIndex byExtendingSelection:NO];
    }
    
    [label1TextField setHidden:NO];
    label1TextField.stringValue = @"degrees";

    [value1TextField setHidden:NO];
    value1TextField.stringValue = degreesString;
    
    [label2TextField setHidden:YES];
    label2TextField.stringValue = @"";

    [value2TextField setHidden:YES];
    value2TextField.stringValue = @"";
    
    [label3TextField setHidden:YES];
    label3TextField.stringValue = @"";

    [value3TextField setHidden:YES];
    value3TextField.stringValue = @"";

    [value4TextField setHidden:YES];
    value4TextField.stringValue = @"";

    [value5TextField setHidden:YES];
    value5TextField.stringValue = @"";

    [value6TextField setHidden:YES];
    value6TextField.stringValue = @"";

    functionButton.hidden = YES;

    transformsTableView.nextKeyView = value1TextField;
    value1TextField.nextKeyView = transformsTableView;
    [value2TextField setNextKeyView:NULL];
    [value3TextField setNextKeyView:NULL];
    
    [self setTransformAttribute];

    float currentDegrees = 0.0f;
    NSString * degreesAttribute = skewXTransformDictionary[@"degrees"];
    if (degreesAttribute != NULL)
    {
        if (degreesAttribute.length > 0)
        {
            currentDegrees = degreesAttribute.floatValue;
        }
    }

    handleDegrees = currentDegrees;
}

//==================================================================================
//	handleMouseMoveEventForSkewX:
//==================================================================================

-(void) handleMouseMoveEventForSkewX:(DOMEvent *)event
{
    //NSLog(@"handleMouseMoveEventForSkewX");
    
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    if (selectedRow != -1)
    {
        NSMutableDictionary * skewXDictionary = (self.transformsArray)[selectedRow];

        NSRect boundingBox = [self.webKitInterface bBoxForDOMElement:self.pluginTargetDOMElement];

        float bboxY = boundingBox.origin.y;
        float bboxHeight = boundingBox.size.height;

        
        float bboxYMax = bboxY + bboxHeight;
        
        float bboxYMid = (bboxY + bboxYMax) / 2.0f;

        float skewDegrees = 0;
        
        NSPoint pointA = NSZeroPoint;
        NSPoint pointB = NSZeroPoint;
        NSPoint pointC = NSZeroPoint;

        NSPoint translatedClickPoint = [self translatePoint:clickPoint targetElement:self.pluginTargetDOMElement.parentElement];
        NSPoint translatedMousePoint = [self translatePoint:currentMousePoint targetElement:self.pluginTargetDOMElement.parentElement];

        if ([handle_orientation isEqualToString:@"top"] == YES)
        {
            pointA = NSMakePoint(translatedClickPoint.x, bboxY);
            pointB = NSMakePoint(translatedClickPoint.x, bboxYMax);
            pointC = NSMakePoint(translatedMousePoint.x, bboxY);
            skewDegrees = -getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"left"] == YES)
        {
            pointA = NSMakePoint(translatedClickPoint.x, bboxY);
            pointB = NSMakePoint(translatedClickPoint.x, bboxYMid);
            pointC = NSMakePoint(translatedMousePoint.x, bboxY);
            skewDegrees = -getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"bottom"] == YES)
        {
            pointA = NSMakePoint(translatedMousePoint.x, bboxYMax);
            pointB = NSMakePoint(translatedClickPoint.x, bboxY);
            pointC = NSMakePoint(translatedClickPoint.x, bboxYMax);
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"right"] == YES)
        {
            pointA = NSMakePoint(translatedMousePoint.x, bboxYMid);
            pointB = NSMakePoint(translatedClickPoint.x, bboxY);
            pointC = NSMakePoint(translatedClickPoint.x, bboxYMid);
            skewDegrees = -getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"topLeft"] == YES)
        {
            pointA = NSMakePoint(translatedClickPoint.x, bboxY);
            pointB = NSMakePoint(translatedClickPoint.x, bboxYMax);
            pointC = NSMakePoint(translatedMousePoint.x, bboxY);
            pointC.x *= currentScale;
            skewDegrees = -getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"topRight"] == YES)
        {
            pointA = NSMakePoint(translatedClickPoint.x, bboxY);
            pointB = NSMakePoint(translatedClickPoint.x, bboxYMax);
            pointC = NSMakePoint(translatedMousePoint.x, bboxY);
            skewDegrees = -getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"bottomLeft"] == YES)
        {
            pointA = NSMakePoint(translatedMousePoint.x, bboxYMax);
            pointB = NSMakePoint(translatedClickPoint.x, bboxY);
            pointC = NSMakePoint(translatedClickPoint.x, bboxYMax);
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"bottomRight"] == YES)
        {
            pointA = NSMakePoint(translatedMousePoint.x, bboxYMax);
            pointB = NSMakePoint(translatedClickPoint.x, bboxY);
            pointC = NSMakePoint(translatedClickPoint.x, bboxYMax);
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }

        if (mouseMoveCount == 1)
        {
            [self.macSVGPluginCallbacks pushUndoRedoDocumentChanges];
        }
        
        // update the positions of the selected SVG elements
        DOMElement * aSvgElement = self.pluginTargetDOMElement;

        NSString * elementName = aSvgElement.nodeName;
        if ((self.validElementsForTransformDictionary)[elementName] != NULL)
        {
            NSString * transformAttributeString = [aSvgElement getAttribute:@"transform"];
            
            if ((transformAttributeString != NULL))
            {
                NSString * newDegreesString = [self allocFloatString:skewDegrees];
                
                skewXDictionary[@"degrees"] = newDegreesString;
                
                value1TextField.stringValue = newDegreesString;
            }
            
            [self setTransformAttribute];
        }
    }
}    

//==================================================================================
//	beginSkewYTransform
//==================================================================================

-(void) beginSkewYTransform
{
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    BOOL makeNewSkewYItem = NO;

    NSMutableDictionary * skewYTransformDictionary = NULL;

    NSString * degreesString = @"0";
    
    if (selectedRow == -1)
    {
        makeNewSkewYItem = YES;
    }
    else
    {
        skewYTransformDictionary =
                (self.transformsArray)[selectedRow];
        
        NSString * selectedFunction = skewYTransformDictionary[@"function"];
        
        if ([selectedFunction isEqualToString:@"skewY"] == YES)
        {
            degreesString = skewYTransformDictionary[@"degrees"];
        }
        else
        {
            // current selection is not a translate, so append a new translate function
            makeNewSkewYItem = YES;
        }
    }
    
    if (makeNewSkewYItem == YES)
    {
        // no row selected, create a new item for the command
        skewYTransformDictionary =   [[NSMutableDictionary alloc] init];
        
        skewYTransformDictionary[@"function"] = @"skewY";
        skewYTransformDictionary[@"degrees"] = degreesString;
        
        selectedRow++;
        
        [self.transformsArray insertObject:skewYTransformDictionary atIndex:selectedRow];

        [transformsTableView reloadData];
        
        NSIndexSet * rowIndex = [[NSIndexSet alloc] initWithIndex:selectedRow];
        
        [transformsTableView selectRowIndexes:rowIndex byExtendingSelection:NO];
    }
    
    [label1TextField setHidden:NO];
    label1TextField.stringValue = @"degrees";

    [value1TextField setHidden:NO];
    value1TextField.stringValue = degreesString;
    
    [label2TextField setHidden:YES];
    label2TextField.stringValue = @"";

    [value2TextField setHidden:YES];
    value2TextField.stringValue = @"";
    
    [label3TextField setHidden:YES];
    label3TextField.stringValue = @"";

    [value3TextField setHidden:YES];
    value3TextField.stringValue = @"";

    [value4TextField setHidden:YES];
    value4TextField.stringValue = @"";

    [value5TextField setHidden:YES];
    value5TextField.stringValue = @"";

    [value6TextField setHidden:YES];
    value6TextField.stringValue = @"";

    functionButton.hidden = YES;

    transformsTableView.nextKeyView = value1TextField;
    value1TextField.nextKeyView = transformsTableView;
    [value2TextField setNextKeyView:NULL];
    [value3TextField setNextKeyView:NULL];
    
    [self setTransformAttribute];

    float currentDegrees = 0.0f;
    NSString * degreesAttribute = skewYTransformDictionary[@"degrees"];
    if (degreesAttribute != NULL)
    {
        if (degreesAttribute.length > 0)
        {
            currentDegrees = degreesAttribute.floatValue;
        }
    }
    
    handleDegrees = currentDegrees;
}


//==================================================================================
//	handleMouseMoveEventForSkewY:
//==================================================================================

-(void) handleMouseMoveEventForSkewY:(DOMEvent *)event
{
    //NSLog(@"handleMouseMoveEventForSkewY");
    
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    if (selectedRow != -1)
    {
        NSMutableDictionary * skewYDictionary = (self.transformsArray)[selectedRow];

        NSRect boundingBox = [self.webKitInterface bBoxForDOMElement:self.pluginTargetDOMElement];

        float bboxX = boundingBox.origin.x;
        float bboxWidth = boundingBox.size.width;
        
        float bboxXMax = bboxX + bboxWidth;
        
        float bboxXMid = (bboxX + bboxXMax) / 2.0f;

        float skewDegrees = 0;
        
        NSPoint pointA = NSZeroPoint;
        NSPoint pointB = NSZeroPoint;
        NSPoint pointC = NSZeroPoint;

        NSPoint translatedClickPoint = [self translatePoint:clickPoint targetElement:self.pluginTargetDOMElement.parentElement];
        NSPoint translatedMousePoint = [self translatePoint:currentMousePoint targetElement:self.pluginTargetDOMElement.parentElement];

        if ([handle_orientation isEqualToString:@"top"] == YES)
        {
            pointA = NSMakePoint(bboxXMid, translatedClickPoint.y);
            pointB = NSMakePoint(bboxXMax, translatedClickPoint.y);
            pointC = NSMakePoint(bboxXMid, translatedMousePoint.y);
            pointC.y *= currentScale;
            skewDegrees = -getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"left"] == YES)
        {
            pointA = NSMakePoint(bboxX, translatedClickPoint.y);
            pointB = NSMakePoint(bboxXMax, translatedClickPoint.y);
            pointC = NSMakePoint(bboxX, translatedMousePoint.y);
            pointC.y *= currentScale;
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"bottom"] == YES)
        {
            pointA = NSMakePoint(bboxXMid, translatedMousePoint.y);
            pointA.y *= currentScale;
            pointB = NSMakePoint(bboxXMax, translatedClickPoint.y);
            pointC = NSMakePoint(bboxXMid, translatedClickPoint.y);
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"right"] == YES)
        {
            pointA = NSMakePoint(bboxXMax, translatedMousePoint.y);
            pointA.y *= currentScale;
            pointB = NSMakePoint(bboxX, translatedClickPoint.y);
            pointC = NSMakePoint(bboxXMax, translatedClickPoint.y);
            skewDegrees = -getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"topLeft"] == YES)
        {
            pointA = NSMakePoint(bboxX, translatedClickPoint.y);
            pointB = NSMakePoint(bboxXMax, translatedClickPoint.y);
            pointC = NSMakePoint(bboxX, translatedMousePoint.y);
            pointC.y *= currentScale;
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"topRight"] == YES)
        {
            pointA = NSMakePoint(bboxXMax, translatedClickPoint.y);
            pointB = NSMakePoint(bboxX, translatedClickPoint.y);
            pointC = NSMakePoint(bboxXMax, translatedMousePoint.y);
            pointC.y *= currentScale;
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"bottomLeft"] == YES)
        {
            pointA = NSMakePoint(bboxX, translatedClickPoint.y);
            pointB = NSMakePoint(bboxXMax, translatedClickPoint.y);
            pointC = NSMakePoint(bboxX, translatedMousePoint.y);
            pointC.y *= currentScale;
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }
        else if ([handle_orientation isEqualToString:@"bottomRight"] == YES)
        {
            pointA = NSMakePoint(bboxXMax, translatedClickPoint.y);
            pointB = NSMakePoint(bboxX, translatedClickPoint.y);
            pointC = NSMakePoint(bboxXMax, translatedMousePoint.y);
            pointC.y *= currentScale;
            skewDegrees = getAngleABC(pointA, pointB, pointC) + handleDegrees;
        }

        if (mouseMoveCount == 1)
        {
            [self.macSVGPluginCallbacks pushUndoRedoDocumentChanges];
        }
        
        // update the positions of the selected SVG elements
        DOMElement * aSvgElement = self.pluginTargetDOMElement;

        NSString * elementName = aSvgElement.nodeName;
        if ((self.validElementsForTransformDictionary)[elementName] != NULL)
        {
            NSString * transformAttributeString = [aSvgElement getAttribute:@"transform"];
            
            if ((transformAttributeString != NULL))
            {
                NSString * newDegreesString = [self allocFloatString:skewDegrees];
                
                skewYDictionary[@"degrees"] = newDegreesString;
                
                value1TextField.stringValue = newDegreesString;
            }
            
            [self setTransformAttribute];
        }
    }
}    

//==================================================================================
//	beginMatrixTransform
//==================================================================================

-(void) beginMatrixTransform
{
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    BOOL makeNewTranslateItem = NO;
    
    NSString * m1String = @"1";     // identity matrix
    NSString * m2String = @"0";
    NSString * m3String = @"0";
    NSString * m4String = @"1";
    NSString * m5String = @"0";
    NSString * m6String = @"0";
    
    if (selectedRow == -1)
    {
        makeNewTranslateItem = YES;
    }
    else
    {
        NSMutableDictionary * selectedTransformDictionary =
                (self.transformsArray)[selectedRow];
        
        NSString * selectedFunction = selectedTransformDictionary[@"function"];
        
        if ([selectedFunction isEqualToString:@"matrix"] == YES)
        {
            m1String = selectedTransformDictionary[@"m1"];
            m2String = selectedTransformDictionary[@"m2"];
            m3String = selectedTransformDictionary[@"m3"];
            m4String = selectedTransformDictionary[@"m4"];
            m5String = selectedTransformDictionary[@"m5"];
            m6String = selectedTransformDictionary[@"m6"];
        }
        else
        {
            // current selection is not a translate, so append a new translate function
            makeNewTranslateItem = YES;
        }
    }
    
    if (makeNewTranslateItem == YES)
    {
        // no row selected, create a new item for the command
        NSMutableDictionary * newTransformDictionary =   [[NSMutableDictionary alloc] init];
        
        newTransformDictionary[@"function"] = @"matrix";
        newTransformDictionary[@"m1"] = @"1";   // identity matrix
        newTransformDictionary[@"m2"] = @"0";
        newTransformDictionary[@"m3"] = @"0";
        newTransformDictionary[@"m4"] = @"1";
        newTransformDictionary[@"m5"] = @"0";
        newTransformDictionary[@"m6"] = @"0";
        
        selectedRow++;
        
        //[transformsArray addObject:newTransformDictionary];
        [self.transformsArray insertObject:newTransformDictionary atIndex:selectedRow];
        
        [transformsTableView reloadData];
        
        //selectedRow = [transformsArray count] - 1;
        
        NSIndexSet * rowIndex = [[NSIndexSet alloc] initWithIndex:selectedRow];
        
        [transformsTableView selectRowIndexes:rowIndex byExtendingSelection:NO];
    }
    
    [label1TextField setHidden:NO];
    label1TextField.stringValue = @"m1:";

    [value1TextField setHidden:NO];
    value1TextField.stringValue = m1String;
    
    [label2TextField setHidden:NO];
    label2TextField.stringValue = @"m2:";

    [value2TextField setHidden:NO];
    value2TextField.stringValue = m2String;

    [label3TextField setHidden:NO];
    label3TextField.stringValue = @"m3:";
    
    [value3TextField setHidden:NO];
    value3TextField.stringValue = m3String;

    [label4TextField setHidden:NO];
    label4TextField.stringValue = @"m4:";
    
    [value4TextField setHidden:NO];
    value4TextField.stringValue = m4String;

    [label5TextField setHidden:NO];
    label5TextField.stringValue = @"m5:";
    
    [value5TextField setHidden:NO];
    value5TextField.stringValue = m5String;

    [label6TextField setHidden:NO];
    label6TextField.stringValue = @"m6:";

    [value6TextField setHidden:NO];
    value6TextField.stringValue = m6String;

    functionButton.hidden = YES;
    
    transformsTableView.nextKeyView = value1TextField;
    value1TextField.nextKeyView = value2TextField;
    value2TextField.nextKeyView = transformsTableView;
    [value3TextField setNextKeyView:NULL];
    
    [self setTransformAttribute];
}

//==================================================================================
//	calculateViewingScale
//==================================================================================

-(void)calculateViewingScale
{
    currentScale = 1.0f;
    DOMDocument * domDocument = (self.svgWebView).mainFrame.DOMDocument;
    DOMNodeList * svgElementsList = [domDocument getElementsByTagNameNS:svgNamespace localName:@"svg"];
    if (svgElementsList.length > 0)
    {
        DOMNode * svgElementNode = [svgElementsList item:0];
        DOMElement * svgElement = (DOMElement *)svgElementNode;
        currentScale = [self.webKitInterface currentScaleForSvgElement:svgElementNode];
        
        NSString * viewBoxAttribute = [svgElement getAttribute:@"viewBox"];
        
        if (viewBoxAttribute != NULL)
        {
            NSArray * viewBoxValuesArray = [viewBoxAttribute componentsSeparatedByString:@" "];

            float viewBoxMinX = 0;
            float viewBoxMinY = 0;
            float viewBoxWidth = 0;
            float viewBoxHeight = 0;
            
            BOOL viewBoxValuesSet = NO;
            if (viewBoxValuesArray.count == 4)
            {
                NSString * viewBoxMinXString = viewBoxValuesArray[0];
                NSString * viewBoxMinYString = viewBoxValuesArray[1];
                NSString * viewBoxWidthString = viewBoxValuesArray[2];
                NSString * viewBoxHeightString = viewBoxValuesArray[3];
                
                viewBoxMinX = viewBoxMinXString.floatValue;
                viewBoxMinY = viewBoxMinYString.floatValue;
                viewBoxWidth = viewBoxWidthString.floatValue;
                viewBoxHeight = viewBoxHeightString.floatValue;
                
                if (viewBoxWidth > 0)
                {
                    if (viewBoxHeight > 0)
                    {
                        viewBoxValuesSet = YES;
                    }
                }
            }
            
            if (viewBoxValuesSet == YES)
            {
                NSString * widthAttribute = [svgElement getAttribute:@"width"];
                
                if (widthAttribute != NULL)
                {
                    NSString * heightAttribute = [svgElement getAttribute:@"height"];
                    if (heightAttribute != NULL)
                    {
                        float width = widthAttribute.floatValue;
                        float height = heightAttribute.floatValue;
                        
                        if ((width > 0) && (height > 0))
                        {
                            float widthScale = width / viewBoxWidth;
                            float heightScale = height / viewBoxHeight;
                            
                            if (widthScale == heightScale)
                            {
                                currentScale = widthScale;
                            }
                        }
                    }
                }
            }
        }
    }
}

//==================================================================================
//	handleMouseDownEvent:
//==================================================================================

-(void) handleMouseDownEvent:(DOMEvent *)event
{
    [self calculateViewingScale];
    
    // for selecting elements or to initiate dragging for element creation
    mouseMode = MOUSE_DRAGGING;
    
    DOMElement * eventTargetElement = event.target;

    DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
    
    //CGFloat zoomFactor = (self.macSVGPluginCallbacks).zoomFactor;
    //currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));

    NSPoint mouseEventPoint = NSMakePoint(mouseEvent.pageX, mouseEvent.pageY);
    
    //NSPoint transformedMousePoint = [webKitInterface transformPoint:aMousePoint fromElement:svgElement toElement:targetElement];
    NSPoint transformedMousePoint = [self translatePoint:mouseEventPoint targetElement:eventTargetElement.parentElement];
    
    //NSLog(@"event mouse: %f,%f transformed %f,%f", mouseEventPoint.x, mouseEventPoint.y, transformedMousePoint.x, transformedMousePoint.y);
    
    currentMousePoint = transformedMousePoint;
    
    CGFloat zoomFactor = [self.macSVGPluginCallbacks scaleForDOMElementHandles:eventTargetElement];
    



/*
    float clientX = mouseEvent.clientX;
    float clientY = mouseEvent.clientY;
    float screenX = mouseEvent.screenX;
    float screenY = mouseEvent.screenY;
    float offsetX = mouseEvent.offsetX;
    float offsetY = mouseEvent.offsetY;
    float pageX = mouseEvent.pageX;
    float pageY = mouseEvent.pageY;
    float layerX = mouseEvent.layerX;
    float layerY = mouseEvent.layerY;
    float aX = mouseEvent.x;
    float aY = mouseEvent.y;
*/

    clickPoint = currentMousePoint;
    
    previousMousePoint = currentMousePoint;
        
    [event preventDefault];
    [event stopPropagation];
        
    selectionHandleClicked = NO;
    handle_orientation = NULL;
    NSString * classAttribute = [eventTargetElement getAttribute:@"class"];
    if ([classAttribute isEqualToString:@"_macsvg_selectionHandle"] == YES)
    {
        selectionHandleClicked = YES;
        handle_orientation = NULL;
        NSString * newHandleOrientation = [eventTargetElement getAttribute:@"_macsvg_handle_orientation"];
        
        // assign a static value to handle_orientation
        if ([newHandleOrientation isEqualToString:@"top"] == YES)
        {
            handle_orientation = @"top";
        }
        else if ([newHandleOrientation isEqualToString:@"left"] == YES)
        {
            handle_orientation = @"left";
        }
        else if ([newHandleOrientation isEqualToString:@"bottom"] == YES)
        {
            handle_orientation = @"bottom";
        }
        else if ([newHandleOrientation isEqualToString:@"right"] == YES)
        {
            handle_orientation = @"right";
        }
        else if ([newHandleOrientation isEqualToString:@"topLeft"] == YES)
        {
            handle_orientation = @"topLeft";
        }
        else if ([newHandleOrientation isEqualToString:@"topRight"] == YES)
        {
            handle_orientation = @"topRight";
        }
        else if ([newHandleOrientation isEqualToString:@"bottomLeft"] == YES)
        {
            handle_orientation = @"bottomLeft";
        }
        else if ([newHandleOrientation isEqualToString:@"bottomRight"] == YES)
        {
            handle_orientation = @"bottomRight";
        }
        
        //NSLog(@"handleMouseDownEvent - handle_orientation=%@", handle_orientation);
    }
    
    elementRectAtMouseDown = NSZeroRect;
    DOMDocument * domDocument = (self.svgWebView).mainFrame.DOMDocument;
    DOMNodeList * svgElementsList = [domDocument getElementsByTagNameNS:svgNamespace localName:@"svg"];
    DOMElement * svgRootElement = NULL;
    if (svgElementsList.length > 0)
    {
        DOMNode * svgElementNode = [svgElementsList item:0];
        svgRootElement = (DOMElement *)svgElementNode;
        elementRectAtMouseDown = [self.webKitInterface pageRectForElement:self.pluginTargetDOMElement svgRootElement:svgRootElement];
    }
    
    mouseMoveCount = 0;

    switch (currentTransformToolMode) 
    {
        case transformToolModeNone:
            break;
        case transformToolModeTranslate:
        {
            if (selectionHandleClicked == NO)
            {
                [self beginTranslateTransform];
            }
            break;
        }
        case transformToolModeScale:
        {
            if (selectionHandleClicked == YES)
            {
                [self beginScaleTransform];
            }
            break;
        }
        case transformToolModeRotate:
        {
            if (selectionHandleClicked == YES)
            {
                [self beginRotateTransform];
            }
            break;
        }
        case transformToolModeSkewX:
        {
            if (selectionHandleClicked == YES)
            {
                [self beginSkewXTransform];
            }
            break;
        }
        case transformToolModeSkewY:
        {
            if (selectionHandleClicked == YES)
            {
                [self beginSkewYTransform];
            }
            break;
        }
        default:
        break;
    }

    if (selectionHandleClicked == YES)
    {
        // user clicked on a selection handle
    }
}

//==================================================================================
//	handleMouseMoveEvent:
//==================================================================================

-(void) handleMouseMoveEvent:(DOMEvent *)event
{
    // handle dragging events

    DOMNode * targetNode = self.pluginTargetDOMElement;
    DOMElement * targetElement = (DOMElement *)targetNode;

    DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
    
    previousMousePoint = currentMousePoint;
    
    //CGFloat zoomFactor = (self.macSVGPluginCallbacks).zoomFactor;
    //currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));

    NSPoint mouseEventPoint = NSMakePoint(mouseEvent.pageX, mouseEvent.pageY);
    
    NSPoint transformedMousePoint = [self translatePoint:mouseEventPoint targetElement:targetElement.parentElement];
    
    //NSLog(@"event mouse: %f,%f transformed %f,%f", mouseEventPoint.x, mouseEventPoint.y, transformedMousePoint.x, transformedMousePoint.y);
    
    currentMousePoint = transformedMousePoint;
    
    CGFloat zoomFactor = [self.macSVGPluginCallbacks scaleForDOMElementHandles:targetElement];



    [event preventDefault];
    [event stopPropagation];

    mouseMoveCount++;
    
    NSString * idAttribute = [targetElement getAttribute:@"id"];
    #pragma unused(idAttribute)

    if (selectionHandleClicked == YES)
    {
        switch (currentTransformToolMode) 
        {
            case transformToolModeNone:
                break;
            case transformToolModeTranslate:
            {
                [self handleMouseMoveEventForTranslate:event];
                break;
            }
            case transformToolModeScale:
            {
                [self handleMouseMoveEventForScale:event];
                break;
            }
            case transformToolModeRotate:
            {
                [self handleMouseMoveEventForRotate:event];
                break;
            }
            case transformToolModeSkewX:
            {
                [self handleMouseMoveEventForSkewX:event];
                break;
            }
            case transformToolModeSkewY:
            {
                [self handleMouseMoveEventForSkewY:event];
                break;
            }
            default:
            break;
        }
    }
    else
    {
        switch (currentTransformToolMode)
        {
            case transformToolModeNone:
                break;
            case transformToolModeTranslate:
            {
                [self handleMouseMoveEventForTranslate:event];
                break;
            }
            case transformToolModeScale:
            {
                break;
            }
            case transformToolModeRotate:
            {
                break;
            }
            case transformToolModeSkewX:
            {
                break;
            }
            case transformToolModeSkewY:
            {
                break;
            }
            default:
            break;
        }
    }
}

//==================================================================================
//	handleMouseUpEvent:
//==================================================================================

-(void) handleMouseUpEvent:(DOMEvent *)event
{
    switch (currentTransformToolMode) 
    {
        case transformToolModeTranslate:
        case transformToolModeRotate:
        case transformToolModeScale:
        case transformToolModeSkewX:
        case transformToolModeSkewY:
        {
            break;
        }
        default:
        {
            break;
        }
    }

    if (mouseMode == MOUSE_DRAGGING)
    {
        mouseMode = MOUSE_DISENGAGED;
    }

    DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
    CGFloat zoomFactor = (self.macSVGPluginCallbacks).zoomFactor;
    currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));

    previousMousePoint = currentMousePoint;

    [event preventDefault];
    [event stopPropagation];
        
    clickPoint = currentMousePoint;
    clickTarget = NULL;
    
    selectionHandleClicked = NO;
    handle_orientation = NULL;
}

//==================================================================================
//	handlePluginEvent
//==================================================================================

-(void) handlePluginEvent:(DOMEvent *)event
{
    // Our callback from WebKit
    NSString * eventType = event.type;
    
    DOMNode * targetNode = self.pluginTargetDOMElement;
    
    DOMElement * targetElement = (DOMElement *)targetNode;
    NSString * tagName = targetElement.tagName;
    #pragma unused(tagName)

    if ([eventType isEqualToString:@"dblclick"] == YES) // use mouseUp instead
    {
        //NSLog(@"handlePluginEvent dblclick");
    }
    else if ([eventType isEqualToString:@"mousedown"] == YES)
    {
        //NSLog(@"handlePluginEvent mousedown");
        [self handleMouseDownEvent:event];
    }
    else if ([eventType isEqualToString:@"mousemove"] == YES)
    {
        //NSLog(@"handlePluginEvent mousemove");
        if (mouseMode == MOUSE_DRAGGING)
        {
            [self handleMouseMoveEvent:event];
        }
    }
    else if ([eventType isEqualToString:@"mouseup"] == YES)
    {
        //NSLog(@"handlePluginEvent mouseup");
        [self handleMouseUpEvent:event];
    }
    else if ([eventType isEqualToString:@"focus"] == YES)
    {
        //NSLog(@"handlePluginEvent focus");
    }
    else if ([eventType isEqualToString:@"blur"] == YES)
    {
        //NSLog(@"handlePluginEvent blur");
    }
    else if ([eventType isEqualToString:@"keydown"] == YES)
    {
        //NSLog(@"handlePluginEvent keydown");
    }
    else if ([eventType isEqualToString:@"keypress"] == YES)
    {
        //NSLog(@"handlePluginEvent keypress");
    }
    else if ([eventType isEqualToString:@"keyup"] == YES)
    {
        //NSLog(@"handlePluginEvent keyup");
    }
}

//==================================================================================
//	parseTransformAttribute
//==================================================================================

- (void)parseTransformAttribute:(NSString *)transformAttribute
{
    NSArray * transformComponentsArray = [transformAttribute componentsSeparatedByString:@")"];
    if (transformComponentsArray.count > 0)
    {
        for (NSString * aTransform in transformComponentsArray)
        {
            NSArray * aTransformComponentsArray = [aTransform componentsSeparatedByString:@"("];
            if (aTransformComponentsArray.count == 2)
            {
                NSCharacterSet * whitespaceCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

                NSString * untrimmedCommandString = aTransformComponentsArray[0];
                NSString * commandString = [untrimmedCommandString 
                        stringByTrimmingCharactersInSet:whitespaceCharacterSet];

                BOOL validCommand = NO;
                //NSUInteger expectedParameters = 0;
                
                if ([commandString isEqualToString:@"translate"] == YES)
                {
                    validCommand = YES;
                }
                else if ([commandString isEqualToString:@"scale"] == YES)
                {
                    validCommand = YES;
                }
                else if ([commandString isEqualToString:@"rotate"] == YES)
                {
                    validCommand = YES;
                }
                else if ([commandString isEqualToString:@"matrix"] == YES)
                {
                    validCommand = YES;
                }
                else if ([commandString isEqualToString:@"skewX"] == YES)
                {
                    validCommand = YES;
                }
                else if ([commandString isEqualToString:@"skewY"] == YES)
                {
                    validCommand = YES;
                }
                
                if (validCommand == YES)
                {
                    NSString * untrimmedValuesString = aTransformComponentsArray[1];
                    NSString * valuesStringWithCommas = [untrimmedValuesString 
                            stringByTrimmingCharactersInSet:whitespaceCharacterSet];
                    NSMutableString * valuesString = [[NSMutableString alloc] 
                            initWithString:valuesStringWithCommas];
                    NSRange valuesStringRange = NSMakeRange(0, valuesString.length);
                    NSUInteger replaceCount = 
                            [valuesString replaceOccurrencesOfString:@"," withString:@" " 
                            options:0 range:valuesStringRange];
                    #pragma unused(replaceCount)
                    
                    NSArray * valuesArray = [valuesString componentsSeparatedByString:@" "];
                    
                    //NSLog(@"Found transform command %@ values:\n%@", commandString, valuesArray);
                    
                    NSMutableDictionary * transformDictionary = [[NSMutableDictionary alloc] init];
                    
                    NSString * functionString = [[NSString alloc] initWithString:commandString];
                    transformDictionary[@"function"] = functionString;
                    
                    NSUInteger valuesCount = valuesArray.count;
                    BOOL validValues = NO;
                    
                    if ([commandString isEqualToString:@"translate"] == YES)
                    {
                        if (valuesCount == 2)
                        {
                            validValues = YES;
                            NSString * xString = [[NSString alloc] initWithString:valuesArray[0]];
                            transformDictionary[@"x"] = xString;
                            
                            NSString * yString = [[NSString alloc] initWithString:valuesArray[1]];
                            transformDictionary[@"y"] = yString;
                        }
                    }
                    else if ([commandString isEqualToString:@"scale"] == YES)
                    {
                        if (valuesCount == 1)
                        {
                            validValues = YES;
                            NSString * xString = [[NSString alloc] initWithString:valuesArray[0]];
                            transformDictionary[@"x"] = xString;
                        }
                        else if (valuesCount == 2)
                        {
                            validValues = YES;
                            NSString * xString = [[NSString alloc] initWithString:valuesArray[0]];
                            transformDictionary[@"x"] = xString;
                            
                            NSString * yString = [[NSString alloc] initWithString:valuesArray[1]];
                            transformDictionary[@"y"] = yString;
                        }
                    }
                    else if ([commandString isEqualToString:@"rotate"] == YES)
                    {
                        if (valuesCount == 1)
                        {
                            validValues = YES;
                            NSString * degreesString = [[NSString alloc] initWithString:valuesArray[0]];
                            transformDictionary[@"degrees"] = degreesString;
                        }
                        else if (valuesCount == 3)
                        {
                            validValues = YES;
                            NSString * degreesString = [[NSString alloc] initWithString:valuesArray[0]];
                            transformDictionary[@"degrees"] = degreesString;

                            NSString * xString = [[NSString alloc] initWithString:valuesArray[1]];
                            transformDictionary[@"x"] = xString;
                            
                            NSString * yString = [[NSString alloc] initWithString:valuesArray[2]];
                            transformDictionary[@"y"] = yString;
                        }
                    }
                    else if ([commandString isEqualToString:@"matrix"] == YES)
                    {
                        if (valuesCount == 6)
                        {
                            validValues = YES;
                            NSString * m1String = [[NSString alloc] initWithString:valuesArray[0]];
                            transformDictionary[@"m1"] = m1String;

                            NSString * m2String = [[NSString alloc] initWithString:valuesArray[1]];
                            transformDictionary[@"m2"] = m2String;

                            NSString * m3String = [[NSString alloc] initWithString:valuesArray[2]];
                            transformDictionary[@"m3"] = m3String;

                            NSString * m4String = [[NSString alloc] initWithString:valuesArray[3]];
                            transformDictionary[@"m4"] = m4String;

                            NSString * m5String = [[NSString alloc] initWithString:valuesArray[4]];
                            transformDictionary[@"m5"] = m5String;

                            NSString * m6String = [[NSString alloc] initWithString:valuesArray[5]];
                            transformDictionary[@"m6"] = m6String;
                        }
                    }
                    else if ([commandString isEqualToString:@"skewX"] == YES)
                    {
                        if (valuesCount == 1)
                        {
                            validValues = YES;
                            NSString * xString = [[NSString alloc] initWithString:valuesArray[0]];
                            transformDictionary[@"degrees"] = xString;
                        }
                    }
                    else if ([commandString isEqualToString:@"skewY"] == YES)
                    {
                        if (valuesCount == 1)
                        {
                            validValues = YES;
                            NSString * yString = [[NSString alloc] initWithString:valuesArray[0]];
                            transformDictionary[@"degrees"] = yString;
                        }
                    }
                    
                    if (validValues == YES)
                    {
                        [self.transformsArray addObject:transformDictionary];
                    }
                }
            }
        }
    }
}

//==================================================================================
//	buildTransformsArrayForElement
//==================================================================================

- (void)buildTransformsArrayForElement
{
    [self.transformsArray removeAllObjects];

    if (self.pluginTargetXMLElement != NULL)
    {
        NSXMLNode * transformAttributeNode = [self.pluginTargetXMLElement attributeForName:@"transform"];
        
        if (transformAttributeNode != NULL)
        {
            NSString * transformAttribute = transformAttributeNode.stringValue;
            
            [self parseTransformAttribute:transformAttribute];
        }
    }
    
    [transformsTableView reloadData];
}

//==================================================================================
//	beginEditForXMLElement:domElement:attributeName:existingValue:
//==================================================================================

- (BOOL)beginEditForXMLElement:(NSXMLElement *)newPluginTargetXMLElement
        domElement:(DOMElement *)newPluginTargetDOMElement
        attributeName:(NSString *)newAttributeName existingValue:(NSString *)existingValue
{
    BOOL result = [super beginEditForXMLElement:newPluginTargetXMLElement
            domElement:newPluginTargetDOMElement attributeName:newAttributeName
            existingValue:existingValue];
    
    translateToolButton.state = NSOffState;
    scaleToolButton.state = NSOffState;
    rotateToolButton.state = NSOffState;
    skewXToolButton.state = NSOffState;
    skewYToolButton.state = NSOffState;

    [self.transformsArray removeAllObjects];

    [label1TextField setHidden:YES];
    label1TextField.stringValue = @"";

    [value1TextField setHidden:YES];
    value1TextField.stringValue = @"";
    
    [label2TextField setHidden:YES];
    label2TextField.stringValue = @"";

    [value2TextField setHidden:YES];
    value2TextField.stringValue = @"";
    
    [label3TextField setHidden:YES];
    label3TextField.stringValue = @"";

    [value3TextField setHidden:YES];
    value3TextField.stringValue = @"";

    [label4TextField setHidden:YES];
    label4TextField.stringValue = @"";

    [value4TextField setHidden:YES];
    value4TextField.stringValue = @"";

    [label5TextField setHidden:YES];
    label5TextField.stringValue = @"";

    [value5TextField setHidden:YES];
    value5TextField.stringValue = @"";

    [label6TextField setHidden:YES];
    label6TextField.stringValue = @"";

    [value6TextField setHidden:YES];
    value6TextField.stringValue = @"";

    functionButton.hidden = YES;

    [transformsTableView deselectAll:self];

    [self buildTransformsArrayForElement];

    return result;
}

//==================================================================================
//	beginEditForXMLElement:domElement:
//==================================================================================

- (BOOL)beginEditForXMLElement:(NSXMLElement *)newPluginTargetXMLElement
        domElement:(DOMElement *)newPluginTargetDOMElement
{
    BOOL result = [super beginEditForXMLElement:newPluginTargetXMLElement
            domElement:newPluginTargetDOMElement];
            
    return result;
}

//==================================================================================
//	copyTextFieldValuesToTransformDictionary:
//==================================================================================

- (void)copyTextFieldValuesToTransformDictionary:(NSMutableDictionary *)transformDictionary
{
    NSString * value1String = value1TextField.stringValue;
    NSString * value2String = value2TextField.stringValue;
    NSString * value3String = value3TextField.stringValue;
    NSString * value4String = value4TextField.stringValue;
    NSString * value5String = value5TextField.stringValue;
    NSString * value6String = value6TextField.stringValue;
    
    NSString * function = transformDictionary[@"function"];
    
    if ([function isEqualToString:@"translate"] == YES)
    {
        NSString * xString = [[NSString alloc] initWithString:value1String];
        transformDictionary[@"x"] = xString;
        
        NSString * yString = [[NSString alloc] initWithString:value2String];
        transformDictionary[@"y"] = yString;
    }
    else if ([function isEqualToString:@"scale"] == YES)
    {
        NSString * xString = [[NSString alloc] initWithString:value1String];
        transformDictionary[@"x"] = xString;
        
        NSString * yString = [[NSString alloc] initWithString:value2String];
        transformDictionary[@"y"] = yString;
    }
    else if ([function isEqualToString:@"rotate"] == YES)
    {
        NSString * degreesString = [[NSString alloc] initWithString:value1String];
        transformDictionary[@"degrees"] = degreesString;
        
        NSString * xString = [[NSString alloc] initWithString:value2String];
        transformDictionary[@"x"] = xString;
        
        NSString * yString = [[NSString alloc] initWithString:value3String];
        transformDictionary[@"y"] = yString;
    }
    else if ([function isEqualToString:@"skewX"] == YES)
    {
        NSString * degreesString = [[NSString alloc] initWithString:value1String];
        transformDictionary[@"degrees"] = degreesString;
    }
    else if ([function isEqualToString:@"skewY"] == YES)
    {
        NSString * degreesString = [[NSString alloc] initWithString:value1String];
        transformDictionary[@"degrees"] = degreesString;
    }
    else if ([function isEqualToString:@"matrix"] == YES)
    {
        NSString * m1String = [[NSString alloc] initWithString:value1String];
        transformDictionary[@"m1"] = m1String;

        NSString * m2String = [[NSString alloc] initWithString:value2String];
        transformDictionary[@"m2"] = m2String;

        NSString * m3String = [[NSString alloc] initWithString:value3String];
        transformDictionary[@"m3"] = m3String;

        NSString * m4String = [[NSString alloc] initWithString:value4String];
        transformDictionary[@"m4"] = m4String;

        NSString * m5String = [[NSString alloc] initWithString:value5String];
        transformDictionary[@"m5"] = m5String;

        NSString * m6String = [[NSString alloc] initWithString:value6String];
        transformDictionary[@"m6"] = m6String;
    }

    [transformsTableView reloadData];
    
    [self setTransformAttribute];
}

//==================================================================================
//	transformToolTextFieldAction
//==================================================================================

- (IBAction)transformToolTextFieldAction:(id)sender;
{
    NSInteger selectedRow = transformsTableView.selectedRow;

    if (selectedRow != -1)
    {
        NSMutableDictionary * transformDictionary = (self.transformsArray)[selectedRow];

        [self copyTextFieldValuesToTransformDictionary:transformDictionary];
    }    
}

//==================================================================================
//	tableViewSelectionDidChange:
//==================================================================================

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	id aTableView = aNotification.object;
	if (aTableView == transformsTableView)
	{
        NSUInteger rowCount = transformsTableView.numberOfRows;
        #pragma unused(rowCount)
        NSUInteger transformsArrayCount = (self.transformsArray).count;
        #pragma unused(transformsArrayCount)
    
        NSInteger selectedRow = transformsTableView.selectedRow;
        
        if (selectedRow != -1)
        {
            NSMutableDictionary * selectedTransformDictionary =
                    (self.transformsArray)[selectedRow];
            
            NSString * selectedFunction = selectedTransformDictionary[@"function"];
            
            if ([selectedFunction isEqualToString:@"translate"] == YES)
            {
                [self selectToolButton:translateToolButton];
            }
            else if ([selectedFunction isEqualToString:@"scale"] == YES)
            {
                [self selectToolButton:scaleToolButton];
            }
            else if ([selectedFunction isEqualToString:@"rotate"] == YES)
            {
                [self selectToolButton:rotateToolButton];
            }
            else if ([selectedFunction isEqualToString:@"skewX"] == YES)
            {
                [self selectToolButton:skewXToolButton];
            }
            else if ([selectedFunction isEqualToString:@"skewY"] == YES)
            {
                [self selectToolButton:skewYToolButton];
            }
            else if ([selectedFunction isEqualToString:@"matrix"] == YES)
            {
                //[self selectToolButton:matrixToolButton];
                
                // matrixToolButton doesn't exist yet
                currentTransformToolMode = transformToolModeMatrix;
                translateToolButton.state = NSOffState;
                scaleToolButton.state = NSOffState;
                rotateToolButton.state = NSOffState;
                skewXToolButton.state = NSOffState;
                skewYToolButton.state = NSOffState;
                
                [self beginMatrixTransform];
            }

            [self.macSVGDocument beginPluginEditorToolMode];
        }
	}
}


//==================================================================================
//	selectToolButton:
//==================================================================================

- (void)selectToolButton:(id)sender
{
    if (settingToolButton == NO)
    {
        settingToolButton = YES;

        if (sender == translateToolButton)
        {
            currentTransformToolMode = transformToolModeTranslate;
            translateToolButton.state = NSOnState;
            scaleToolButton.state = NSOffState;
            rotateToolButton.state = NSOffState;
            skewXToolButton.state = NSOffState;
            skewYToolButton.state = NSOffState;
            
            [self beginTranslateTransform];
        }
        else if (sender == scaleToolButton)
        {
            currentTransformToolMode = transformToolModeScale;
            translateToolButton.state = NSOffState;
            scaleToolButton.state = NSOnState;
            rotateToolButton.state = NSOffState;
            skewXToolButton.state = NSOffState;
            skewYToolButton.state = NSOffState;
            
            [self beginScaleTransform];
        }
        else if (sender == rotateToolButton)
        {
            currentTransformToolMode = transformToolModeRotate;
            translateToolButton.state = NSOffState;
            scaleToolButton.state = NSOffState;
            rotateToolButton.state = NSOnState;
            skewXToolButton.state = NSOffState;
            skewYToolButton.state = NSOffState;

            [self beginRotateTransform];
        }
        else if (sender == skewXToolButton)
        {
            currentTransformToolMode = transformToolModeSkewX;
            translateToolButton.state = NSOffState;
            scaleToolButton.state = NSOffState;
            rotateToolButton.state = NSOffState;
            skewXToolButton.state = NSOnState;
            skewYToolButton.state = NSOffState;
            
            [self beginSkewXTransform];
        }
        else if (sender == skewYToolButton)
        {
            currentTransformToolMode = transformToolModeSkewY;
            translateToolButton.state = NSOffState;
            scaleToolButton.state = NSOffState;
            rotateToolButton.state = NSOffState;
            skewXToolButton.state = NSOffState;
            skewYToolButton.state = NSOnState;
            
            [self beginSkewYTransform];
        }

        settingToolButton = NO;
    }
}

//==================================================================================
//	transformToolButtonAction:
//==================================================================================

- (IBAction)transformToolButtonAction:(id)sender
{
    [self selectToolButton:sender];
    
    [transformsTableView reloadData];
    
    [self.macSVGDocument beginPluginEditorToolMode];
}

//==================================================================================
//	transformToolDeleteButtonAction:
//==================================================================================

- (IBAction)transformToolDeleteButtonAction:(id)sender;
{
    NSInteger selectedRow = transformsTableView.selectedRow;
    
    if (selectedRow != -1)
    {
        [self.transformsArray removeObjectAtIndex:selectedRow];
    
        [transformsTableView reloadData];
        
        [self setTransformAttribute];
    }
}

//==================================================================================
//	functionButtonAction:
//==================================================================================

- (IBAction)functionButtonAction:(id)sender
{
     NSInteger selectedRow = transformsTableView.selectedRow;

    if (selectedRow != -1)
    {
        NSMutableDictionary * transformDictionary = (self.transformsArray)[selectedRow];
        NSString * functionString = transformDictionary[@"function"];
        
        if ([functionString isEqualToString:@"rotate"] == YES)
        {
            NSString * originalRotationValue = value1TextField.stringValue;
            value1TextField.stringValue = @"0";

            [self copyTextFieldValuesToTransformDictionary:transformDictionary];    // temporarily set rotation to zero
        
            NSRect boundingBox = [self.webKitInterface bBoxForDOMElement:self.pluginTargetDOMElement];
            float bboxX = boundingBox.origin.x;
            float bboxY = boundingBox.origin.y;
            float bboxWidth = boundingBox.size.width;
            float bboxHeight = boundingBox.size.height;
            
            
            float bboxXMax = bboxX + bboxWidth;
            float bboxYMax = bboxY + bboxHeight;
            
            float bboxXCenter = (bboxX + bboxXMax) * 0.5f;
            float bboxYCenter = (bboxY + bboxYMax) * 0.5f;
            
            NSString * centerXString = [self allocFloatString:bboxXCenter];
            NSString * centerYString = [self allocFloatString:bboxYCenter];
            
            value1TextField.stringValue = originalRotationValue;    // restore original rotation and set new center point
            value2TextField.stringValue = centerXString;
            value3TextField.stringValue = centerYString;

            [self copyTextFieldValuesToTransformDictionary:transformDictionary];
        
            [transformsTableView reloadData];
        }
    }    

}


@end
