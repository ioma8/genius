//  Genius
//
//  This code is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 2.5 License.
//  http://creativecommons.org/licenses/by-nc-sa/2.5/

#import <Foundation/Foundation.h>


@interface GeniusAssociationDataPoint : NSObject <NSCoding> {
	NSDate * _date;  //!< The date on which this info is recorded.
	float _value;    //!< How well did they remember the item.
}

- (id) initWithDate:(NSDate *)date value:(float)value;

- (NSDate *) date;
- (BOOL) value;

@end


@interface GeniusAssociationDataPoint (GradePrediction)

+ (float) predictedValueWithDataPoints:(NSArray *)dataPoints;

+ (NSTimeInterval) timeIntervalForCount:(unsigned int)count;	// XXX: used by GeniusAssociationEnumerator

@end
