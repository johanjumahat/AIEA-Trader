//+------------------------------------------------------------------+
//| Dashboard.mqh — On-Chart Performance Dashboard                     |
//| AIEA Trader — Self-Improving MT5 AI Trading EA                    |
//+------------------------------------------------------------------+
#ifndef AIEA_DASHBOARD_MQH
#define AIEA_DASHBOARD_MQH

#include "Config.mqh"
#include "TradingJournal.mqh"
#include "LearningEngine.mqh"
#include "StrategyEvolution.mqh"
#include "RiskManager.mqh"
#include "IndicatorEngine.mqh"
#include "NewsManager.mqh"

#define DASHBOARD_PREFIX "AIEA_"

//--- Format a number with thousand separators, e.g. 490016.62 -> "490,016.62"
string FormatMoney(double value, int decimals = 2)
{
   bool neg = (value < 0.0);
   if(neg) value = -value;

   string numStr = DoubleToString(value, decimals);
   int dotPos = StringFind(numStr, ".");

   string intPart  = (dotPos >= 0) ? StringSubstr(numStr, 0, dotPos) : numStr;
   string decPart  = (dotPos >= 0) ? StringSubstr(numStr, dotPos)    : "";

   string result = "";
   int len = StringLen(intPart);
   int count = 0;
   for(int i = len - 1; i >= 0; i--)
   {
      result = StringSubstr(intPart, i, 1) + result;
      count++;
      if(count % 3 == 0 && i != 0)
         result = "," + result;
   }

   return (neg ? "-" : "") + result + decPart;
}

//==================================================================
//  DASHBOARD CLASS
//==================================================================

class CDashboard
{
private:
   CTradingJournal    *m_journal;
   CLearningEngine     *m_learningEngine;
   CStrategyEvolution  *m_evolution;
   CRiskManager        *m_riskManager;
   CNewsManager        *m_newsManager;

   void   CreateLabel(string name, string text, int x, int y,
                      color clr = clrWhite, int fontSize = 10,
                      string font = "Consolas");
   void   CreateRect(string name, int x, int y, int width, int height,
                     color bgClr);
   void   UpdateLabel(string name, string text, color clr = clrWhite);
   void   UpdateWrappedLabel(string baseName, string fullText, color clr, int maxLineLen = 46);

public:
   CDashboard();
   ~CDashboard();

   bool   Init(CTradingJournal &jrnl, CLearningEngine &lrnEngine,
               CStrategyEvolution &evolution, CRiskManager &rskMgr,
               CNewsManager &newsMgr);
   void   Create();
   void   Update();
   void   Destroy();
};

//--- Constructor
CDashboard::CDashboard()
{
   m_journal = NULL;
   m_learningEngine = NULL;
   m_evolution = NULL;
   m_riskManager = NULL;
   m_newsManager = NULL;
}

//--- Destructor
CDashboard::~CDashboard()
{
}

//--- Initialize
bool CDashboard::Init(CTradingJournal &jrnl, CLearningEngine &lrnEngine,
                       CStrategyEvolution &evolution, CRiskManager &rskMgr,
                       CNewsManager &newsMgr)
{
   m_journal = GetPointer(jrnl);
   m_learningEngine = GetPointer(lrnEngine);
   m_evolution = GetPointer(evolution);
   m_riskManager = GetPointer(rskMgr);
   m_newsManager = GetPointer(newsMgr);
   return true;
}

//--- Create a text label
void CDashboard::CreateLabel(string name, string text, int x, int y,
                               color clr, int fontSize, string font)
{
   string objName = DASHBOARD_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetString(0, objName, OBJPROP_FONT, font);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
}

//--- Create a background rectangle
void CDashboard::CreateRect(string name, int x, int y, int width, int height,
                             color bgClr)
{
   string objName = DASHBOARD_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
}

//--- Update a label's text
void CDashboard::UpdateLabel(string name, string text, color clr)
{
   string objName = DASHBOARD_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
   {
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   }
}

//--- Update a label that may need to wrap across 2 pre-created lines
// (baseName + "1" / baseName + "2") so long text never overflows the panel.
void CDashboard::UpdateWrappedLabel(string baseName, string fullText, color clr, int maxLineLen)
{
   if(StringLen(fullText) > maxLineLen)
   {
      int splitPos = maxLineLen;
      for(int i = maxLineLen; i > maxLineLen - 20 && i > 0; i--)
      {
         if(StringGetCharacter(fullText, i) == ' ')
         {
            splitPos = i;
            break;
         }
      }
      UpdateLabel(baseName + "1", StringSubstr(fullText, 0, splitPos), clr);
      UpdateLabel(baseName + "2", StringSubstr(fullText, splitPos), clr);
   }
   else
   {
      UpdateLabel(baseName + "1", fullText, clr);
      UpdateLabel(baseName + "2", " ", clr);
   }
}

//--- Create the dashboard
// Layout: two aligned, non-overlapping boxes, both x=10, width=460, stacked
// vertically with a 10px gap between them:
//   Box 1 (y=20..240):  Account + Performance stats — split into LEFT/RIGHT
//                        columns so it takes half the vertical space of the
//                        old single-column layout, then a full-width Strategy
//                        row underneath.
//   Box 2 (y=250..400): Standalone Economic News panel (previously crammed
//                        into the bottom of Box 1, causing overlap with the
//                        separate Market Status panel below it).
void CDashboard::Create()
{
   //=== BOX 1: Account / Performance / Strategy (2-column) ===
   CreateRect("bg", 10, 20, 400, 220, C'20,20,30');

   CreateLabel("title", "AIEA Trader — Dashboard", 20, 30, clrGold, 12, "Consolas");
   CreateLabel("sep1", "──────────────────────", 20, 48, clrDimGray, 10, "Consolas");

   // LEFT column — Account (label x=20, value x=140)
   CreateLabel("equity_lbl", "Equity:", 20, 62, clrGray, 10, "Consolas");
   CreateLabel("equity_val", "---", 140, 62, clrWhite, 10, "Consolas");

   CreateLabel("balance_lbl", "Balance:", 20, 78, clrGray, 10, "Consolas");
   CreateLabel("balance_val", "---", 140, 78, clrWhite, 10, "Consolas");

   CreateLabel("dd_lbl", "Drawdown:", 20, 94, clrGray, 10, "Consolas");
   CreateLabel("dd_val", "---", 140, 94, clrWhite, 10, "Consolas");

   CreateLabel("daily_pnl_lbl", "Daily P&L:", 20, 110, clrGray, 10, "Consolas");
   CreateLabel("daily_pnl_val", "---", 140, 110, clrWhite, 10, "Consolas");

   // RIGHT column — Performance (label x=250, value x=370), same rows as left
   CreateLabel("trades_lbl", "Total Trades:", 220, 62, clrGray, 10, "Consolas");
   CreateLabel("trades_val", "0", 330, 62, clrWhite, 10, "Consolas");

   CreateLabel("winrate_lbl", "Win Rate:", 220, 78, clrGray, 10, "Consolas");
   CreateLabel("winrate_val", "---", 330, 78, clrWhite, 10, "Consolas");

   CreateLabel("pf_lbl", "Profit Factor:", 220, 94, clrGray, 10, "Consolas");
   CreateLabel("pf_val", "---", 330, 94, clrWhite, 10, "Consolas");

   CreateLabel("exp_lbl", "Expectancy:", 220, 110, clrGray, 10, "Consolas");
   CreateLabel("exp_val", "---", 330, 110, clrWhite, 10, "Consolas");

   // Full-width separator
   CreateLabel("sep2", "──────────────────────", 20, 128, clrDimGray, 10, "Consolas");

   // Strategy section (full width, single column)
   CreateLabel("profile_lbl", "Active Profile:", 20, 142, clrGray, 10, "Consolas");
   CreateLabel("profile_val", "---", 140, 142, clrAqua, 10, "Consolas");

   CreateLabel("profile_score_lbl", "Profile Score:", 20, 158, clrGray, 10, "Consolas");
   CreateLabel("profile_score_val", "---", 140, 158, clrWhite, 10, "Consolas");

   CreateLabel("status_lbl", "Status:", 20, 174, clrGray, 10, "Consolas");
   CreateLabel("status_val", "ACTIVE", 140, 174, clrLime, 10, "Consolas");

   CreateLabel("halt_lbl", " ", 20, 190, clrRed, 10, "Consolas");

   CreateLabel("sep3", "──────────────────────", 20, 206, clrDimGray, 10, "Consolas");

   //=== BOX 2: Standalone Economic News panel ===
   // Starts 10px below Box 1 (20 + 220 + 10 = 250), same x/width for alignment.
   CreateRect("news_bg", 10, 250, 400, 150, C'20,20,30');

   CreateLabel("news_title", "⚠ ECONOMIC NEWS", 20, 260, clrGold, 11, "Consolas");
   CreateLabel("news_sep1", "──────────────────────", 20, 278, clrDimGray, 10, "Consolas");

   // Table header for the fixed-width columns produced by GetNewsDisplayString()
   CreateLabel("news_header", "TIME   IMP  CTY  ETA", 20, 292, clrGray, 9, "Consolas");

   CreateLabel("news_line1", "---", 20, 306, clrSilver, 9, "Consolas");
   CreateLabel("news_line2", "---", 20, 320, clrSilver, 9, "Consolas");
   CreateLabel("news_line3", "---", 20, 334, clrSilver, 9, "Consolas");

   CreateLabel("news_sep2", "──────────────────────", 20, 352, clrDimGray, 10, "Consolas");

   // Warning/protection line — wraps across 2 lines so long messages never overflow
   CreateLabel("news_warning1", " ", 20, 366, clrRed, 10, "Consolas");
   CreateLabel("news_warning2", " ", 20, 381, clrRed, 10, "Consolas");
}

//--- Update dashboard values
void CDashboard::Update()
{
   if(m_riskManager == NULL) return;

   // Account info
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double peakEquity = m_riskManager.GetPeakEquity();
   double drawdown = 0.0;
   if(peakEquity > 0.0)
      drawdown = (peakEquity - equity) / peakEquity * 100.0;

   UpdateLabel("equity_val", FormatMoney(equity, 2));
   UpdateLabel("balance_val", FormatMoney(balance, 2));
   UpdateLabel("dd_val", StringFormat("%.1f%%", drawdown),
               (drawdown > 10.0 ? clrRed : (drawdown > 5.0 ? clrYellow : clrLime)));

   double dailyPnL = m_riskManager.GetDailyProfit();
   UpdateLabel("daily_pnl_val", FormatMoney(dailyPnL, 2),
               (dailyPnL >= 0.0 ? clrLime : clrRed));

   // Performance metrics
   if(m_learningEngine != NULL && m_evolution != NULL)
   {
      int activeId = m_evolution.GetActiveProfileId();
      int tradeCount = m_learningEngine.GetTradeCount(activeId);
      double winRate = m_learningEngine.GetWinRate(activeId);
      double pf = m_learningEngine.GetProfitFactor(activeId);
      double exp = m_learningEngine.GetExpectancy(activeId);

      UpdateLabel("trades_val", (string)tradeCount);
      UpdateLabel("winrate_val", StringFormat("%.1f%%", winRate),
                  (winRate >= 50.0 ? clrLime : (winRate >= 35.0 ? clrYellow : clrRed)));
      UpdateLabel("pf_val", StringFormat("%.2f", pf),
                  (pf >= 1.5 ? clrLime : (pf >= 1.0 ? clrYellow : clrRed)));
      UpdateLabel("exp_val", FormatMoney(exp, 2),
                  (exp >= 0.0 ? clrLime : clrRed));

      // Profile info
      ParameterSet ps;
      if(m_evolution.GetProfileById(activeId, ps))
      {
         UpdateLabel("profile_val", StringFormat("#%d %s", ps.id, ps.name));
         UpdateLabel("profile_score_val", StringFormat("%.1f/100", ps.score),
                     (ps.score >= 60.0 ? clrLime : (ps.score >= 40.0 ? clrYellow : clrRed)));
      }
   }

   // Status
   if(m_riskManager.IsHalted())
   {
      UpdateLabel("status_val", "HALTED", clrRed);
      UpdateLabel("halt_lbl", m_riskManager.GetHaltReason(), clrRed);
   }
   else
   {
      UpdateLabel("status_val", "ACTIVE", clrLime);
      UpdateLabel("halt_lbl", " ", clrBlack);
   }

   // === NEWS SECTION (standalone box) ===
   if(m_newsManager != NULL)
   {
      string display = m_newsManager.GetNewsDisplayString();
      string lines[5];
      int numLines = StringSplit(display, (ushort)'\n', lines);

      UpdateLabel("news_line1", (numLines > 0 ? lines[0] : "---"), clrSilver);
      UpdateLabel("news_line2", (numLines > 1 ? lines[1] : "---"), clrSilver);
      UpdateLabel("news_line3", (numLines > 2 ? lines[2] : "---"), clrSilver);

      // Warning banner — wraps across 2 lines so it never overflows the box
      string warning = m_newsManager.GetWarningMessage();
      string protStatus = m_newsManager.GetProtectionStatus();

      if(protStatus != "")
         UpdateWrappedLabel("news_warning", protStatus, clrOrange, 54);
      else if(warning != "")
         UpdateWrappedLabel("news_warning", warning, clrRed, 54);
      else
         UpdateWrappedLabel("news_warning", " ", clrBlack, 54);
   }
}

//--- Destroy all dashboard objects
void CDashboard::Destroy()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, DASHBOARD_PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

#endif // AIEA_DASHBOARD_MQH
//+------------------------------------------------------------------+
