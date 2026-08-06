//+------------------------------------------------------------------+
//| TradingJournal.mqh — Trade Journal Database (File-Based)         |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_TRADING_JOURNAL_MQH
#define AIEA_TRADING_JOURNAL_MQH

#include "Config.mqh"

//==================================================================
//  TRADING JOURNAL CLASS
//==================================================================

class CTradingJournal
{
private:
   string   m_fileName;
   string   m_folderName;
   int      m_nextId;

   string  EscapeCSV(const string value);
   string  RegimeToString(ENUM_MARKET_REGIME regime);
   string  OutcomeToString(ENUM_TRADE_OUTCOME outcome);
   string  EntryQualityToString(ENUM_ENTRY_QUALITY q);
   string  ExitQualityToString(ENUM_EXIT_QUALITY q);
   string  SLAssessmentToString(ENUM_SL_ASSESSMENT sl);
   string  TPAssessmentToString(ENUM_TP_ASSESSMENT tp);

public:
   CTradingJournal();
   ~CTradingJournal();

   bool   Init(string folder = "AIEA_Trader");
   bool   WriteEntry(const JournalEntry &je);
   bool   ReadAllEntries(JournalEntry &entries[], int &count);
   bool   ReadEntriesByProfile(int profileId, JournalEntry &entries[], int &count);
   int    GetTotalEntries();
   bool   ClearAll();
   string GetFileName() { return m_folderName + "\\" + m_fileName; }
};

//--- Constructor
CTradingJournal::CTradingJournal()
{
   m_fileName = "journal.csv";
   m_folderName = "AIEA_Trader";
   m_nextId = 1;
}

//--- Destructor
CTradingJournal::~CTradingJournal()
{
}

//--- Escape CSV field
string CTradingJournal::EscapeCSV(const string value)
{
   string result = value;
   StringReplace(result, "\"", "\"\"");
   return "\"" + result + "\"";
}

//--- Enum to string helpers
string CTradingJournal::RegimeToString(ENUM_MARKET_REGIME regime)
{
   switch(regime)
   {
      case REGIME_TRENDING: return "Trending";
      case REGIME_RANGING:  return "Ranging";
      case REGIME_VOLATILE: return "Volatile";
      default:             return "Unknown";
   }
}

string CTradingJournal::OutcomeToString(ENUM_TRADE_OUTCOME outcome)
{
   switch(outcome)
   {
      case OUTCOME_WIN:       return "Win";
      case OUTCOME_LOSS:      return "Loss";
      case OUTCOME_BREAKEVEN: return "Breakeven";
      default:                return "Pending";
   }
}

string CTradingJournal::EntryQualityToString(ENUM_ENTRY_QUALITY q)
{
   switch(q)
   {
      case ENTRY_OPTIMAL: return "Optimal";
      case ENTRY_AVERAGE: return "Average";
      case ENTRY_POOR:    return "Poor";
      default:            return "Unknown";
   }
}

string CTradingJournal::ExitQualityToString(ENUM_EXIT_QUALITY q)
{
   switch(q)
   {
      case EXIT_OPTIMAL: return "Optimal";
      case EXIT_AVERAGE: return "Average";
      case EXIT_POOR:    return "Poor";
      default:           return "Unknown";
   }
}

string CTradingJournal::SLAssessmentToString(ENUM_SL_ASSESSMENT sl)
{
   switch(sl)
   {
      case SL_TOO_TIGHT:    return "Too Tight";
      case SL_APPROPRIATE:  return "Appropriate";
      case SL_TOO_WIDE:     return "Too Wide";
      default:              return "Unknown";
   }
}

string CTradingJournal::TPAssessmentToString(ENUM_TP_ASSESSMENT tp)
{
   switch(tp)
   {
      case TP_TOO_CLOSE:    return "Too Close";
      case TP_APPROPRIATE:  return "Appropriate";
      case TP_TOO_FAR:      return "Too Far";
      default:              return "Unknown";
   }
}

//--- Initialize journal
bool CTradingJournal::Init(string folder)
{
   m_folderName = folder;
   m_fileName   = "journal.csv";

   // Create folder if it doesn't exist
   if(!FolderCreate(m_folderName))
   {
      // Folder may already exist — that's fine
      if(GetLastError() != 5007) // ERR_DIRECTORY_NOT_EXIST is expected if folder needs creation
      {
         Print("[Journal] Folder creation note: ", m_folderName);
      }
   }

   // Write header if file doesn't exist
   string fullPath = m_folderName + "\\" + m_fileName;
   if(!FileIsExist(fullPath, 0))
   {
      int handle = FileOpen(fullPath, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
      {
         Print("[Journal] Failed to create journal file: ", fullPath, " error: ", GetLastError());
         return false;
      }

      FileWrite(handle,
         "Ticket", "Symbol", "OpenTime", "CloseTime", "Type",
         "OpenPrice", "ClosePrice", "StopLoss", "TakeProfit", "Volume",
         "Profit", "MFE", "MAE", "Spread", "Slippage", "Confidence",
         "EntryRationale", "ExitRationale", "Outcome",
         "EntryQuality", "ExitQuality", "SLAssessment", "TPAssessment",
         "Regime", "ProfileId",
         "RSI", "MAFast", "MASlow", "BBUpper", "BBLower",
         "MACDMain", "MACDSignal", "StochMain", "ATR",
         "VolatilityPct", "Weekday", "Hour", "Session",
         "LessonLearned", "RiskReward", "RuleCompliant", "PerformanceImpact"
      );

      FileClose(handle);
   }

   // Count existing entries to determine next ID
   m_nextId = GetTotalEntries() + 1;

   return true;
}

//--- Write a journal entry
bool CTradingJournal::WriteEntry(const JournalEntry &je)
{
   string fullPath = m_folderName + "\\" + m_fileName;

   int handle = FileOpen(fullPath, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("[Journal] Failed to open journal file: ", GetLastError());
      return false;
   }

   // Seek to end
   FileSeek(handle, 0, SEEK_END);

   FileWrite(handle,
      (string)je.ticket,
      EscapeCSV(je.symbol),
      (string)je.openTime,
      (string)je.closeTime,
      (string)je.type,
      DoubleToString(je.openPrice, 5),
      DoubleToString(je.closePrice, 5),
      DoubleToString(je.stopLoss, 5),
      DoubleToString(je.takeProfit, 5),
      DoubleToString(je.volume, 2),
      DoubleToString(je.profit, 2),
      DoubleToString(je.mfe, 1),
      DoubleToString(je.mae, 1),
      DoubleToString(je.spreadAtEntry, 1),
      DoubleToString(je.slippage, 1),
      DoubleToString(je.confidence, 1),
      EscapeCSV(je.entryRationale),
      EscapeCSV(je.exitRationale),
      OutcomeToString(je.outcome),
      EntryQualityToString(je.entryQuality),
      ExitQualityToString(je.exitQuality),
      SLAssessmentToString(je.slAssessment),
      TPAssessmentToString(je.tpAssessment),
      RegimeToString(je.regime),
      (string)je.profileId,
      DoubleToString(je.rsiAtEntry, 2),
      DoubleToString(je.maFastAtEntry, 5),
      DoubleToString(je.maSlowAtEntry, 5),
      DoubleToString(je.bbUpperAtEntry, 5),
      DoubleToString(je.bbLowerAtEntry, 5),
      DoubleToString(je.macdMainAtEntry, 5),
      DoubleToString(je.macdSignalAtEntry, 5),
      DoubleToString(je.stochMainAtEntry, 2),
      DoubleToString(je.atrAtEntry, 5),
      DoubleToString(je.volatilityPercent, 2),
      (string)je.weekday,
      (string)je.hour,
      EscapeCSV(je.session),
      EscapeCSV(je.lessonLearned),
      DoubleToString(je.riskRewardRatio, 2),
      (je.ruleCompliant ? "Yes" : "No"),
      DoubleToString(je.performanceImpact, 2)
   );

   FileClose(handle);
   m_nextId++;

   return true;
}

//--- Read all entries (simplified — returns count, entries populated)
bool CTradingJournal::ReadAllEntries(JournalEntry &entries[], int &count)
{
   string fullPath = m_folderName + "\\" + m_fileName;
   count = 0;

   int handle = FileOpen(fullPath, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   // Skip header line
   for(int i = 0; i < 41; i++)
   {
      if(FileIsEnding(handle)) { FileClose(handle); return true; }
      FileReadString(handle);
   }

   while(!FileIsEnding(handle))
   {
      // This is a simplified reader — in production, parse all fields
      string ticket = FileReadString(handle);
      if(ticket == "") break;

      JournalEntry je;
      InitJournalEntry(je);
      je.ticket = (int)StringToInteger(ticket);
      je.symbol = FileReadString(handle);
      je.openTime = (datetime)StringToInteger(FileReadString(handle));
      je.closeTime = (datetime)StringToInteger(FileReadString(handle));
      je.type = (int)StringToInteger(FileReadString(handle));
      je.openPrice = StringToDouble(FileReadString(handle));
      je.closePrice = StringToDouble(FileReadString(handle));
      je.stopLoss = StringToDouble(FileReadString(handle));
      je.takeProfit = StringToDouble(FileReadString(handle));
      je.volume = StringToDouble(FileReadString(handle));
      je.profit = StringToDouble(FileReadString(handle));
      je.mfe = StringToDouble(FileReadString(handle));
      je.mae = StringToDouble(FileReadString(handle));
      je.spreadAtEntry = StringToDouble(FileReadString(handle));
      je.slippage = StringToDouble(FileReadString(handle));
      je.confidence = StringToDouble(FileReadString(handle));
      je.entryRationale = FileReadString(handle);
      je.exitRationale = FileReadString(handle);

      string outcomeStr = FileReadString(handle);
      if(outcomeStr == "Win") je.outcome = OUTCOME_WIN;
      else if(outcomeStr == "Loss") je.outcome = OUTCOME_LOSS;
      else if(outcomeStr == "Breakeven") je.outcome = OUTCOME_BREAKEVEN;

      // Read remaining fields
      FileReadString(handle); // entryQuality
      FileReadString(handle); // exitQuality
      FileReadString(handle); // slAssessment
      FileReadString(handle); // tpAssessment
      string regimeStr = FileReadString(handle);
      if(regimeStr == "Trending") je.regime = REGIME_TRENDING;
      else if(regimeStr == "Ranging") je.regime = REGIME_RANGING;
      else if(regimeStr == "Volatile") je.regime = REGIME_VOLATILE;

      je.profileId = (int)StringToInteger(FileReadString(handle));
      je.rsiAtEntry = StringToDouble(FileReadString(handle));
      je.maFastAtEntry = StringToDouble(FileReadString(handle));
      je.maSlowAtEntry = StringToDouble(FileReadString(handle));
      je.bbUpperAtEntry = StringToDouble(FileReadString(handle));
      je.bbLowerAtEntry = StringToDouble(FileReadString(handle));
      je.macdMainAtEntry = StringToDouble(FileReadString(handle));
      je.macdSignalAtEntry = StringToDouble(FileReadString(handle));
      je.stochMainAtEntry = StringToDouble(FileReadString(handle));
      je.atrAtEntry = StringToDouble(FileReadString(handle));
      je.volatilityPercent = StringToDouble(FileReadString(handle));
      je.weekday = (int)StringToInteger(FileReadString(handle));
      je.hour = (int)StringToInteger(FileReadString(handle));
      je.session = FileReadString(handle);
      je.lessonLearned = FileReadString(handle);
      je.riskRewardRatio = StringToDouble(FileReadString(handle));
      string compliantStr = FileReadString(handle);
      je.ruleCompliant = (compliantStr == "Yes");
      je.performanceImpact = StringToDouble(FileReadString(handle));

      ArrayResize(entries, count + 1);
      entries[count] = je;
      count++;
   }

   FileClose(handle);
   return true;
}

//--- Read entries by profile ID
bool CTradingJournal::ReadEntriesByProfile(int profileId, JournalEntry &entries[], int &count)
{
   JournalEntry allEntries[];
   int totalCount = 0;

   if(!ReadAllEntries(allEntries, totalCount))
      return false;

   count = 0;
   for(int i = 0; i < totalCount; i++)
   {
      if(allEntries[i].profileId == profileId)
      {
         ArrayResize(entries, count + 1);
         entries[count] = allEntries[i];
         count++;
      }
   }

   return true;
}

//--- Get total number of entries
int CTradingJournal::GetTotalEntries()
{
   string fullPath = m_folderName + "\\" + m_fileName;
   int handle = FileOpen(fullPath, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return 0;

   int count = 0;
   // Skip header (41 fields)
   for(int i = 0; i < 41; i++)
   {
      if(FileIsEnding(handle)) { FileClose(handle); return 0; }
      FileReadString(handle);
   }

   while(!FileIsEnding(handle))
   {
      string ticket = FileReadString(handle);
      if(ticket == "") break;

      // Skip the remaining 40 fields of this record
      for(int i = 0; i < 40; i++)
      {
         if(FileIsEnding(handle)) break;
         FileReadString(handle);
      }
      count++;
   }

   FileClose(handle);
   return count;
}

//--- Clear all entries (reset to header only)
bool CTradingJournal::ClearAll()
{
   string fullPath = m_folderName + "\\" + m_fileName;

   int handle = FileOpen(fullPath, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle,
      "Ticket", "Symbol", "OpenTime", "CloseTime", "Type",
      "OpenPrice", "ClosePrice", "StopLoss", "TakeProfit", "Volume",
      "Profit", "MFE", "MAE", "Spread", "Slippage", "Confidence",
      "EntryRationale", "ExitRationale", "Outcome",
      "EntryQuality", "ExitQuality", "SLAssessment", "TPAssessment",
      "Regime", "ProfileId",
      "RSI", "MAFast", "MASlow", "BBUpper", "BBLower",
      "MACDMain", "MACDSignal", "StochMain", "ATR",
      "VolatilityPct", "Weekday", "Hour", "Session",
      "LessonLearned", "RiskReward", "RuleCompliant", "PerformanceImpact"
   );

   FileClose(handle);
   m_nextId = 1;
   return true;
}

#endif // AIEA_TRADING_JOURNAL_MQH
//+------------------------------------------------------------------+
