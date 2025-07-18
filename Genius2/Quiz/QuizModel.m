//  Genius
//
//  This code is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 2.5 License.
//  http://creativecommons.org/licenses/by-nc-sa/2.5/

#import "QuizModel.h"

#import "GeniusAssociation.h"
#import "GeniusItem.h"	// myRating

#import "GeniusPreferences.h"
#import "GeniusDocumentInfo.h"	// -quizDirectionMode
#import "QuizArrayAdditions.h"

#define DEBUG 0


const kQuizModelDefaultRequestedCount = 10;

//! Models a user quiz.
@implementation QuizModel

//! Initialize a QuizModel with the given document as association source.
- (id) initWithDocument:(GeniusDocument *)document
{
	self = [super init];
	_document = [document retain];
	_allActiveAssociations = nil;
	
	_requestedCount = kQuizModelDefaultRequestedCount;
	_requestedReviewLearnFloat = 50.0;
	_requestedMinScore = -1.0;

	return self;
}

//! Free up memory.
- (void) dealloc
{
	[_document release];
	[_allActiveAssociations release];
	[super dealloc];
}

//! returns subset of associations for this document that match our quiz model.
- (NSArray *) _allActiveAssociations
{
	if (_allActiveAssociations == nil)
	{
		NSMutableArray * fragments = [NSMutableArray arrayWithObject:@"(parentItem.isEnabled == YES)"]; // AND (parentItem.atomA.string != NIL) AND (parentItem.atomB.string != NIL)"];

		int quizDirectionMode = [[_document documentInfo] quizDirectionMode];
/*		if (quizDirectionMode == GeniusQuizUnidirectionalMode)
			[fragments addObject:@"(sourceAtomKey == \"atomA\" AND targetAtomKey == \"atomB\")"];
		else
			[fragments addObject:@"((sourceAtomKey == \"atomA\" AND targetAtomKey == \"atomB\") OR (sourceAtomKey == \"atomB\" AND targetAtomKey == \"atomA\"))"];*/
		if (quizDirectionMode == GeniusQuizUnidirectionalMode)
			[fragments addObject:@"(sourceAtom == parentItem.atomA AND targetAtom == parentItem.atomB)"];
		else
			[fragments addObject:@"((sourceAtom == parentItem.atomA AND targetAtom == parentItem.atomB) OR (sourceAtom == parentItem.atomB AND targetAtom == parentItem.atomA))"];

		if (_requestedMinScore != -1.0)
			[fragments addObject:[NSString stringWithFormat:@"(predictedValue >= %f)", _requestedMinScore]];
		
		NSMutableString * query = [NSMutableString string];
		int i, count = [fragments count];
		for (i=0; i<count; i++)
		{
			NSString * fragment = [fragments objectAtIndex:i];
			[query appendString:fragment];
			if (i<count-1)
				[query appendString:@" AND "];
		}

		// Fetch all relevant associations
		NSFetchRequest * request = [[[NSFetchRequest alloc] init] autorelease];
		NSEntityDescription * entity = [NSEntityDescription entityForName:@"GeniusAssociation" inManagedObjectContext:[_document managedObjectContext]];
		[request setEntity:entity];

		NSPredicate * predicate = [NSPredicate predicateWithFormat:query];
		[request setPredicate:predicate];
		
		NSError * error = nil;
		NSArray * associations = [[_document managedObjectContext] executeFetchRequest:request error:&error];
		if (associations == nil)
			NSLog(@"%@", [error description]);

		_allActiveAssociations = [associations retain];
	}
	return _allActiveAssociations;
}

//! Helper method to check if _allActiveAssociations is not empty.
- (BOOL) hasValidItems
{
	NSArray * associations = [self _allActiveAssociations];
	return ([associations count] > 0);
}


//! _requestedCount setter
/*! a count of 0 means all active associations */
- (void) setCount:(unsigned int)count
{
	if (count == 0)
		count = [[self _allActiveAssociations] count];
	_requestedCount = count;
}

//! _requestedReviewLearnFloat setter.
- (void) setReviewLearnFloat:(float)value
{
	_requestedReviewLearnFloat = value;
}

/*- (void) setMinimumScore:(float)score
{
	_requestedMinScore = score;
}*/

//! helper to return _requestedReviewLearnFloat as number between 0 an 2.
- (float) _probabilityCenter
{
	// 0% should be minimum=0 (review only)
	// 50% should be m=1.0
	// 100% should be m=0.0 (learn only)

	if (_requestedReviewLearnFloat == 0.0)
		_requestedMinScore = 0.0;
	
    return ((100.0 - _requestedReviewLearnFloat) / 100.0) * 2.0;
}


//! Function used in sorting array of GeniusAssociation instances by rating attribute.
static NSComparisonResult CompareAssociationByRating(GeniusAssociation * assoc1, GeniusAssociation * assoc2, void *context)
{
    GeniusItem * item1 = [assoc1 valueForKey:@"parentItem"];
    GeniusItem * item2 = [assoc2 valueForKey:@"parentItem"];
    int rating1 = [[item1 valueForKey:@"myRating"] intValue];
    int rating2 = [[item2 valueForKey:@"myRating"] intValue];
    
    if (rating1 > rating2)
        return NSOrderedAscending;
    else if (rating1 < rating2)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}

//! Calculates the factorial of n.
static unsigned long Factorial(int n)
{
    return (n<=1) ? 1 : n * Factorial(n-1);
}

//! Calculates the probablity of x for a given m.
static float PoissonValue(int x, float m)
{
    return (pow(m,x) / Factorial(x)) * pow(M_E, -m);
}

//!  Selects items from @a associations based on GeniusAssociation#score and _m_value.
/*!
    Sorts the associations into buckets based on score.  Then calculates the Poisson value 
    for each bucket based on the established #_probabilityCenter.  Finally generates a series of
    random numbers to choose items from the buckets based on the probablility curve.
 */
- (NSArray *) _chooseAssociationsByWeightedCurve:(NSArray *)associations
{
    #if DEBUG
		// Calculate minimum and maximum scores        
		float minScore = [[associations valueForKeyPath:@"@min.predictedValue"] floatValue];
		float maxScore = [[associations valueForKeyPath:@"@max.predictedValue"] floatValue];		
        NSLog(@"minScore=%f, maxScore=%f", minScore, maxScore);
	NSLog(@"[associations count]=%d, _requestedCount=%d", [associations count], _requestedCount);
    #endif

    if ([associations count] <= _requestedCount)
        return associations;

    // Count the number of buckets necessary.
    NSMutableArray * buckets = [NSMutableArray array];
    int bucketCount = 11; // ((maxScore - minScore) * 10.0) + 1;
    int b;
    for (b=0; b<bucketCount; b++)
        [buckets addObject:[NSMutableArray array]];

    // Sort the associations into buckets.
    NSEnumerator * associationEnumerator = [associations objectEnumerator];
    GeniusAssociation * association;
    while ((association = [associationEnumerator nextObject]))
    {
		float predictedValue = [association predictedValue]; // valueForKey:GeniusAssociationPredictedScoreKey] floatValue];
        b = predictedValue * 10.0;
		if (predictedValue == -1.0)
			b = 0;
		
        NSMutableArray * bucket = [buckets objectAtIndex:b];
        [bucket addObject:association];
    }
    #if DEBUG
    for (b=0; b<bucketCount; b++)
        NSLog(@"bucket[%d] has count %d", b, [[buckets objectAtIndex:b] count]);
    #endif

    // Calculate Poisson distribution curve using _m_value.
	float _m_value = [self _probabilityCenter];
    #if DEBUG
	NSLog(@"_m_value = %f", _m_value);
    #endif

    float * p = calloc(sizeof(float), bucketCount);
    float max_p = 0.0;
    for (b=0; b<bucketCount; b++)
    {
        p[b] = PoissonValue(b, _m_value);
        max_p = MAX(max_p, p[b]);

        #if DEBUG
        NSLog(@"p[%d]=%f --> expect count %.1f", b, p[b], _requestedCount * p[b]);
        #endif
    }

    // Perform weighted random selection of _requestedCount objects
    NSMutableArray * outAssociations = [NSMutableArray array];
    while ([outAssociations count] < _requestedCount)
    {
        float x = random() / (float)LONG_MAX;
        #if DEBUG
        float origValue = x;
        #endif

        // Here we translate the random point x to the index of the corresponding weighted bucket.
        // We assert that the sum of the probabilities (p[b] for all b) is 1.0.
        for (b=0; b<bucketCount; b++)
        {
            if (x < p[b])
            {
                NSMutableArray * bucket = [buckets objectAtIndex:b];
                if ([bucket count] > 0)
                {
                    [outAssociations addObject:[bucket objectAtIndex:0]];
                    [bucket removeObjectAtIndex:0];
                    
                    #if DEBUG
                    NSLog(@"random %f --> pull from bucket %d; %d left", origValue, b, [bucket count]);
                    #endif
                    break;  // done with this association
                }
            }
            x -= p[b];
        }
    }

    free(p);
    
    return outAssociations;
}

//! Helper method to initialize the set of associations for enumeration.
/*!
The process of choosing involves:
 @li Filtering out inactive associations
 @li Randomizing the remaining ones
 @li Sorting the results by importance
 @li Finally choosing at least QuizModel#_requestedCount items based on QuizModel#_requestedMinScore.
 */
- (NSArray *) _chosenAssociations
{
	// 1. First, filter out disabled pairs, minimum scores, and long-term dates.
	NSArray * activeAssociations = [self _allActiveAssociations];
	
	// 2. Shuffle the remaining "active" associations
	NSArray * shuffledAssociations = [activeAssociations _arrayByRandomizing];

	// 3. Weight the associations according to user rating
	NSArray * orderedAssociations = [shuffledAssociations sortedArrayUsingFunction:CompareAssociationByRating context:NULL];

	// 4. Choose n associations by score according to a probability curve
		// Uses _requestedCount, [self _probabilityCenter]
	NSArray * chosenAssociations = [self _chooseAssociationsByWeightedCurve:orderedAssociations];

	return chosenAssociations;
}

//! Convenience method to get a enumerator on _chosenAssociations.
- (GeniusAssociationEnumerator *) associationEnumerator
{
	NSArray * chosenAssociations = [self _chosenAssociations];
	return [[[GeniusAssociationEnumerator alloc] initWithAssociations:chosenAssociations] autorelease];
}

@end
