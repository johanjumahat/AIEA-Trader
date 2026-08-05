//+------------------------------------------------------------------+
//| NewsManager.mqh — Economic News Calendar Manager                  |
//| AIEA Trader — Uses MT5 built-in calendar API (zero credits)       |
//|                                                                   |
//| Features:                                                         |
//|   - Fetches today's high-impact news from broker's calendar       |
//|   - Displays news on chart dashboard                              |
//|   - Warns when high-impact news is within 2 hours                 |
//|   - Optional: blocks trading during news window                   |
//+------------------------------------------------------------------+
#ifndef AIEA_NEWSMANAGER_MQH
#define AIEA_NEWSMANAGER_MQH

#include "Config.mqh"

//==================================================================
//  NEWS DATA STRUCTURES
//==================================================================

struct NewsEvent
{
   datetime   time;           // Event time (server time)
   string     country;        // Country code (US, EU, UK, JP, etc.)
   string     currency;       // Affected currency
   string     title;          // Event title
   int        importance;     // 0=none, 1=low, 2=medium, 3=high
   int        impact;         // 0=none, 1=positive, 2=negative
   double     actual;         // Actual value (0 if not yet released)
   double     forecast;       // Forecast value
   double     previous;       // Previous value
};

#define MAX_NEWS_EVENTS 50

//==================================================================
//  NEWS MANAGER CLASS
//==================================================================

class CNewsManager
{
private:
   NewsEvent   m_events[MAX_NEWS_EVENTS];
   int         m_eventCount;
   datetime    m_lastUpdate;
   int         m_warningHours;    // Hours before news to warn
   int         m_blockMinutes;    // Minutes before/after news to block

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
   string GetNewsDisplayString();
   string GetWarningMessage();
   string GetTodaysNewsSummary();
};

//--- Constructor
CNewsManager::CNewsManager()
{
   m_eventCount = 0;
   m_lastUpdate = 0;
   m_warningHours = 2;
   m_blockMinutes = 15;
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
      ne.impact     = (int)values[i].impact;
      ne.actual     = values[i].actual_value;
      ne.forecast   = values[i].forecast_value;
      ne.previous   = values[i].previous_value;

      m_events[m_eventCount] = ne;
      m_eventCount++;
   }

   m_lastUpdate = TimeCurrent();

   // Sort by time (simple bubble sort, small array)
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

//--- Get a full summary of today's news (for log printing)
string CNewsManager::GetTodaysNewsSummary()
{
   if(m_eventCount == 0)
      return "No medium/high impact news today";

   string summary = StringFormat("Today's News (%d events):\n", m_eventCount);
   for(int i = 0; i < m_eventCount; i++)
   {
      string impStr = (m_events[i].importance == 3 ? "HIGH" : "MED");
      summary += StringFormat("  %s %s %s — %s\n",
                              TimeToString(m_events[i].time, TIME_MINUTES),
                              impStr, m_events[i].country, m_events[i].title);
   }
   return summary;
}

#endif // AIEA_NEWSMANAGER_MQH
