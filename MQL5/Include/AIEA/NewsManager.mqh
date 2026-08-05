//+------------------------------------------------------------------+
//| NewsManager.mqh — Economic News Calendar Manager                  |
//| AIEA Trader — Uses MT5 built-in calendar API (zero credits)       |
//|                                                                   |
//| Features:                                                         |
//|   - Fetches today's high-impact news from broker's calendar       |
//|   - Displays news on chart dashboard                              |
//|   - Warns when high-impact news is within 2 hours                 |
//|   - Blocks trading during news window                            |
//|   - Protects open trades before news: tightens SL to breakeven    |
//|     or places hedge pending order, then restores after news      |
//+------------------------------------------------------------------+
#ifndef AIEA_NEWSMANAGER_MQH
#define AIEA_NEWSMANAGER_MQH

#include "Config.mqh"
#include <Trade/Trade.mqh>

//==================================================================
//  NEWS DATA STRUCTURES
//==================================================================

struct NewsEvent
{
   datetime   time;
   string     country;
   string     currency;
   string     title;
   int        importance;
   int        impact;
   double     actual;
   double     forecast;
   double     previous;
};

//--- Saved SL state for restoring after news protection
struct SavedPosition
{
   ulong    ticket;
   double   originalSL;
   double   originalTP;
   bool     isProtected;
};

#define MAX_NEWS_EVENTS    50
#define MAX_SAVED_POSITIONS 10

//==================================================================
//  NEWS MANAGER CLASS
//==================================================================

class CNewsManager
{
private:
   NewsEvent      m_events[MAX_NEWS_EVENTS];
   int            m_eventCount;
   datetime       m_lastUpdate;
   int            m_warningHours;
   int            m_blockMinutes;

   // News protection state
   int            m_protectMinutes;     // Start protecting N min before news
   int            m_releaseMinutes;     // Release protection N min after news
   bool           m_protectMode;       // 0=off, 1=tighten SL, 2=hedge pending
   bool           m_isProtecting;      // Currently in protection mode
   datetime       m_protectStartTime;  // When we started protecting
   datetime       m_protectEventTime;  // Time of the news event we're protecting for
   SavedPosition  m_savedPositions[MAX_SAVED_POSITIONS];
   int            m_savedCount;
   CTrade         m_trade;
   string         m_symbol;      // Symbol to protect (set via CheckNewsProtection)
   int            m_magicNumber; // Magic number filter (set via CheckNewsProtection)
   bool           m_verbose;     // Verbose logging flag

   bool   FindNextHighImpactEvent(datetime &eventTime);
   void   ApplySLProtection();
   void   RemoveSLProtection();
   void   ApplyHedgeProtection();
   void   RemoveHedgeProtection();

public:
   CNewsManager();
   ~CNewsManager();

   bool   FetchTodaysNews();
   bool   IsNewsWarningActive();
   bool   GetNextHighImpactEvent(NewsEvent &evt);
   bool   IsInNewsBlackout();
   int    GetEventCount() { return m_eventCount; }
   bool   GetEvent(int index, NewsEvent &evt);
   void   SetWarningHours(int hours) { m_warningHours = hours; }
   void   SetBlockMinutes(int minutes) { m_blockMinutes = minutes; }
   void   SetProtectMinutes(int minutes) { m_protectMinutes = minutes; }
   void   SetReleaseMinutes(int minutes) { m_releaseMinutes = minutes; }
   void   SetProtectMode(int mode) { m_protectMode = (mode > 0); }
   string GetNewsDisplayString();
   string GetWarningMessage();
   string GetTodaysNewsSummary();

   // News trade protection
   void   CheckNewsProtection(string symbol, int magicNumber, bool verbose = true);
   bool   IsProtecting() { return m_isProtecting; }
   string GetProtectionStatus();
};

//--- Constructor
CNewsManager::CNewsManager()
{
   m_eventCount = 0;
   m_lastUpdate = 0;
   m_warningHours = 2;
   m_blockMinutes = 15;
   m_protectMinutes = 60;    // Start protecting 60 min before news
   m_releaseMinutes = 60;    // Release 60 min after news
   m_protectMode = true;
   m_isProtecting = false;
   m_protectStartTime = 0;
   m_protectEventTime = 0;
   m_savedCount = 0;
   m_symbol = "";
   m_magicNumber = 0;
   m_verbose = true;
}

//--- Destructor
CNewsManager::~CNewsManager()
{
}

//--- Fetch today's economic news using MT5 built-in calendar
bool CNewsManager::FetchTodaysNews()
{
   m_eventCount = 0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayStart = StructToTime(dt);
   datetime todayEnd = todayStart + 86400;

   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, todayStart, todayEnd);

   if(count <= 0)
   {
      Print("[AIEA News] No calendar events found for today");
      return false;
   }

   for(int i = 0; i < count && m_eventCount < MAX_NEWS_EVENTS; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;

      if(event.importance < CALENDAR_IMPORTANCE_MODERATE)
         continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
         continue;

      NewsEvent ne;
      ne.time       = values[i].time;
      ne.country    = country.code;
      ne.currency   = country.currency;
      ne.title      = event.name;
      ne.importance = (int)event.importance;
      ne.impact     = (int)values[i].impact_type;
      // Calendar numeric values are stored as long, multiplied by 10^6.
      // LONG_MIN means the value is not set — treat as 0 to avoid overflow/NaN.
      ne.actual     = (values[i].actual_value   == LONG_MIN) ? 0.0 : values[i].actual_value   / 1000000.0;
      ne.forecast   = (values[i].forecast_value == LONG_MIN) ? 0.0 : values[i].forecast_value / 1000000.0;
      ne.previous   = (values[i].prev_value     == LONG_MIN) ? 0.0 : values[i].prev_value     / 1000000.0;

      m_events[m_eventCount] = ne;
      m_eventCount++;
   }

   m_lastUpdate = TimeCurrent();

   // Sort by time
   for(int i = 0; i < m_eventCount - 1; i++)
   {
      for(int j = i + 1; j < m_eventCount; j++)
      {
         if(m_events[j].time < m_events[i].time)
         {
            NewsEvent tmp = m_events[i];
            m_events[i] = m_events[j];
            m_events[j] = tmp;
         }
      }
   }

   Print("[AIEA News] Fetched ", m_eventCount, " medium/high impact events for today");

   for(int i = 0; i < m_eventCount; i++)
   {
      string impStr = (m_events[i].importance == 3 ? "HIGH" : "MEDIUM");
      Print("[AIEA News] ", TimeToString(m_events[i].time, TIME_MINUTES),
            " | ", impStr, " | ", m_events[i].country, " | ", m_events[i].title);
   }

   return m_eventCount > 0;
}

//--- Find the next high-impact event time
bool CNewsManager::FindNextHighImpactEvent(datetime &eventTime)
{
   datetime now = TimeCurrent();
   for(int i = 0; i < m_eventCount; i++)
   {
      if(m_events[i].importance >= (int)CALENDAR_IMPORTANCE_HIGH && m_events[i].time >= now)
      {
         eventTime = m_events[i].time;
         return true;
      }
   }
   return false;
}

//--- Check if a high-impact news warning is active
bool CNewsManager::IsNewsWarningActive()
{
   datetime now = TimeCurrent();
   datetime warningEnd = now + (datetime)(m_warningHours * 3600);

   for(int i = 0; i < m_eventCount; i++)
   {
      if(m_events[i].importance >= (int)CALENDAR_IMPORTANCE_HIGH)
      {
         if(m_events[i].time >= now && m_events[i].time <= warningEnd)
            return true;
      }
   }
   return false;
}

//--- Get the next upcoming high-impact event
bool CNewsManager::GetNextHighImpactEvent(NewsEvent &evt)
{
   datetime now = TimeCurrent();
   for(int i = 0; i < m_eventCount; i++)
   {
      if(m_events[i].importance >= (int)CALENDAR_IMPORTANCE_HIGH && m_events[i].time >= now)
      {
         evt = m_events[i];
         return true;
      }
   }
   return false;
}

//--- Check if we're in a news blackout window
bool CNewsManager::IsInNewsBlackout()
{
   datetime now = TimeCurrent();
   datetime blockBefore = now + (datetime)(m_blockMinutes * 60);
   datetime blockAfter  = now - (datetime)(m_blockMinutes * 60);

   for(int i = 0; i < m_eventCount; i++)
   {
      if(m_events[i].importance >= (int)CALENDAR_IMPORTANCE_HIGH)
      {
         if(m_events[i].time <= blockBefore && m_events[i].time >= blockAfter)
            return true;
      }
   }
   return false;
}

//--- Get event by index
bool CNewsManager::GetEvent(int index, NewsEvent &evt)
{
   if(index < 0 || index >= m_eventCount)
      return false;
   evt = m_events[index];
   return true;
}

//--- Build compact display string for dashboard
string CNewsManager::GetNewsDisplayString()
{
   if(m_eventCount == 0)
      return "No news today";

   datetime now = TimeCurrent();
   string result = "";
   int shown = 0;

   for(int i = 0; i < m_eventCount && shown < 3; i++)
   {
      if(m_events[i].time >= now - 3600)
      {
         string impStr = (m_events[i].importance == 3 ? "HIGH" : "MED");
         string timeStr = TimeToString(m_events[i].time, TIME_MINUTES);

         int minsAway = (int)((m_events[i].time - now) / 60);
         string relStr;
         if(minsAway > 0)
            relStr = StringFormat(" (in %dh%dm)", minsAway / 60, minsAway % 60);
         else if(minsAway == 0)
            relStr = " (NOW)";
         else
            relStr = StringFormat(" (%dm ago)", -minsAway);

         result += StringFormat("%s %s %s%s\n", timeStr, impStr, m_events[i].country, relStr);
         shown++;
      }
   }

   if(result == "")
      result = "No upcoming news";

   return result;
}

//--- Get warning message if news is approaching
string CNewsManager::GetWarningMessage()
{
   NewsEvent evt;
   if(!GetNextHighImpactEvent(evt))
      return "";

   datetime now = TimeCurrent();
   int minsAway = (int)((evt.time - now) / 60);

   if(minsAway < 0 || minsAway > m_warningHours * 60)
      return "";

   if(minsAway <= 0)
      return StringFormat("HIGH IMPACT NOW: %s %s", evt.country, evt.title);

   int hours = minsAway / 60;
   int mins  = minsAway % 60;

   return StringFormat("HIGH IMPACT in %dh%dm: %s %s @ %s",
                       hours, mins, evt.country, evt.title,
                       TimeToString(evt.time, TIME_MINUTES));
}

//--- Get protection status string for dashboard
string CNewsManager::GetProtectionStatus()
{
   if(!m_isProtecting)
      return "";

   datetime now = TimeCurrent();
   int minsToNews = (int)((m_protectEventTime - now) / 60);

   if(minsToNews > 0)
      return StringFormat("PROTECTING: SL tightened (news in %dm)", minsToNews);
   else
      return StringFormat("PROTECTING: SL tightened (news %dm ago, release in %dm)",
                          -minsToNews, m_releaseMinutes - (int)((now - m_protectEventTime) / 60));
}

//--- Get a full summary of today's news
string CNewsManager::GetTodaysNewsSummary()
{
   if(m_eventCount == 0)
      return "No medium/high impact news today";

   string summary = StringFormat("Today's News (%d events):\n", m_eventCount);
   for(int i = 0; i < m_eventCount; i++)
   {
      string impStr = (m_events[i].importance == 3 ? "HIGH" : "MED");
      summary += StringFormat("  %s %s %s - %s\n",
                              TimeToString(m_events[i].time, TIME_MINUTES),
                              impStr, m_events[i].country, m_events[i].title);
   }
   return summary;
}

//==================================================================
//  NEWS TRADE PROTECTION
//==================================================================

//--- Main protection check — call on every tick
void CNewsManager::CheckNewsProtection(string symbol, int magicNumber, bool verbose)
{
   if(!m_protectMode)
      return;

   m_symbol = symbol;
   m_magicNumber = magicNumber;
   m_verbose = verbose;

   datetime now = TimeCurrent();
   datetime nextEvent;
   bool hasEvent = FindNextHighImpactEvent(nextEvent);

   if(!m_isProtecting)
   {
      // Check if we should START protecting
      if(hasEvent)
      {
         int minsToNews = (int)((nextEvent - now) / 60);
         if(minsToNews <= m_protectMinutes && minsToNews >= 0)
         {
            m_isProtecting = true;
            m_protectStartTime = now;
            m_protectEventTime = nextEvent;

            Print("[AIEA News] PROTECTION ACTIVATED — high-impact news at ",
                  TimeToString(nextEvent, TIME_MINUTES),
                  " (in ", minsToNews, " min). Tightening SL on open positions.");

            ApplySLProtection();
         }
      }
   }
   else
   {
      // Check if we should STOP protecting
      // Release m_releaseMinutes after the news event
      datetime releaseTime = m_protectEventTime + (datetime)(m_releaseMinutes * 60);

      if(now >= releaseTime)
      {
         Print("[AIEA News] PROTECTION RELEASED — news window passed (",
               m_releaseMinutes, " min after event). Restoring original SLs.");

         RemoveSLProtection();
         m_isProtecting = false;
         m_protectStartTime = 0;
         m_protectEventTime = 0;
      }
      // If we're already past the event but within release window, keep protecting
      else if(now >= m_protectEventTime)
      {
         int minsAfter = (int)((now - m_protectEventTime) / 60);
         int minsLeft = m_releaseMinutes - minsAfter;
         if(m_verbose)
            Print("[AIEA News] Protection active — ", minsAfter,
                  " min after news, releasing in ", minsLeft, " min");
      }
   }
}

//--- Apply SL protection: move SL to breakeven + small buffer on all open positions
void CNewsManager::ApplySLProtection()
{
   m_savedCount = 0;
   string sym = (m_symbol != "") ? m_symbol : _Symbol;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double buffer = point * 10; // 10 points buffer above/below breakeven

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != sym)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long posType = PositionGetInteger(POSITION_TYPE);

      // Save original state
      if(m_savedCount < MAX_SAVED_POSITIONS)
      {
         m_savedPositions[m_savedCount].ticket = ticket;
         m_savedPositions[m_savedCount].originalSL = currentSL;
         m_savedPositions[m_savedCount].originalTP = currentTP;
         m_savedPositions[m_savedCount].isProtected = true;
         m_savedCount++;
      }

      // Calculate breakeven SL
      double newSL;
      if(posType == POSITION_TYPE_BUY)
      {
         newSL = NormalizeDouble(openPrice + buffer, digits);
         // Only tighten — never loosen
         if(newSL > currentSL && newSL < SymbolInfoDouble(sym, SYMBOL_BID))
         {
            m_trade.PositionModify(ticket, newSL, currentTP);
            Print("[AIEA News] Protected BUY #", ticket,
                  " SL moved from ", DoubleToString(currentSL, digits),
                  " to ", DoubleToString(newSL, digits), " (breakeven+", (int)buffer, "pts)");
         }
      }
      else // SELL
      {
         newSL = NormalizeDouble(openPrice - buffer, digits);
         // Only tighten — never loosen
         if((currentSL == 0.0 || newSL < currentSL) && newSL > SymbolInfoDouble(sym, SYMBOL_ASK))
         {
            m_trade.PositionModify(ticket, newSL, currentTP);
            Print("[AIEA News] Protected SELL #", ticket,
                  " SL moved from ", DoubleToString(currentSL, digits),
                  " to ", DoubleToString(newSL, digits), " (breakeven-", (int)buffer, "pts)");
         }
      }
   }

   if(m_savedCount == 0)
      Print("[AIEA News] No open positions to protect");
}

//--- Remove SL protection: restore original SLs (only if tighter than current)
void CNewsManager::RemoveSLProtection()
{
   string sym = (m_symbol != "") ? m_symbol : _Symbol;
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   for(int i = 0; i < m_savedCount; i++)
   {
      ulong ticket = m_savedPositions[i].ticket;
      if(!PositionSelectByTicket(ticket))
      {
         // Position was closed (likely hit the tightened SL) — skip
         Print("[AIEA News] Position #", ticket, " no longer open (likely closed during news)");
         continue;
      }

      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double originalSL = m_savedPositions[i].originalSL;
      long posType = PositionGetInteger(POSITION_TYPE);

      // Only restore if current SL is tighter than original (we tightened it)
      // and the position still belongs to us
      if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber)
         continue;

      bool shouldRestore = false;
      if(posType == POSITION_TYPE_BUY)
      {
         // If original SL was looser (further from price), restore it
         if(originalSL == 0.0 || currentSL > originalSL)
            shouldRestore = true;
      }
      else
      {
         if(originalSL == 0.0 || (currentSL != 0.0 && currentSL < originalSL))
            shouldRestore = true;
      }

      if(shouldRestore)
      {
         m_trade.PositionModify(ticket, originalSL, currentTP);
         Print("[AIEA News] Restored SL on #", ticket,
               " from ", DoubleToString(currentSL, digits),
               " to ", DoubleToString(originalSL, digits));
      }

      m_savedPositions[i].isProtected = false;
   }

   m_savedCount = 0;
}

#endif // AIEA_NEWSMANAGER_MQH
