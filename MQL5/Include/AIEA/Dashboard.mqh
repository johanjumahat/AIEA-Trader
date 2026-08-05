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

//--- Create the dashboard
void CDashboard::Create()
{
   // Background panel
   CreateRect("bg", 10, 20, 380, 420, C'20,20,30');

   // Title
   CreateLabel("title", "AIEA Trader — Dashboard", 20, 30, clrGold, 12, "Consolas");

   // Separator
   CreateLabel("sep1", "─────────────────────────", 20, 50, clrDimGray, 10, "Consolas");

   // Account section
   CreateLabel("equity_lbl", "Equity:", 20, 65, clrGray, 10, "Consolas");
   CreateLabel("equity_val", "---", 150, 65, clrWhite, 10, "Consolas");

   CreateLabel("balance_lbl", "Balance:", 20, 82, clrGray, 10, "Consolas");
   CreateLabel("balance_val", "---", 150, 82, clrWhite, 10, "Consolas");

   CreateLabel("dd_lbl", "Drawdown:", 20, 99, clrGray, 10, "Consolas");
   CreateLabel("dd_val", "---", 150, 99, clrWhite, 10, "Consolas");

   CreateLabel("daily_pnl_lbl", "Daily P&L:", 20, 116, clrGray, 10, "Consolas");
   CreateLabel("daily_pnl_val", "---", 150, 116, clrWhite, 10, "Consolas");

   // Separator
   CreateLabel("sep2", "─────────────────────────", 20, 135, clrDimGray, 10, "Consolas");

   // Performance section
   CreateLabel("trades_lbl", "Total Trades:", 20, 150, clrGray, 10, "Consolas");
   CreateLabel("trades_val", "0", 150, 150, clrWhite, 10, "Consolas");

   CreateLabel("winrate_lbl", "Win Rate:", 20, 167, clrGray, 10, "Consolas");
   CreateLabel("winrate_val", "---", 150, 167, clrWhite, 10, "Consolas");

   CreateLabel("pf_lbl", "Profit Factor:", 20, 184, clrGray, 10, "Consolas");
   CreateLabel("pf_val", "---", 150, 184, clrWhite, 10, "Consolas");

   CreateLabel("exp_lbl", "Expectancy:", 20, 201, clrGray, 10, "Consolas");
   CreateLabel("exp_val", "---", 150, 201, clrWhite, 10, "Consolas");

   // Separator
   CreateLabel("sep3", "─────────────────────────", 20, 220, clrDimGray, 10, "Consolas");

   // Strategy section
   CreateLabel("profile_lbl", "Active Profile:", 20, 235, clrGray, 10, "Consolas");
   CreateLabel("profile_val", "---", 150, 235, clrAqua, 10, "Consolas");

   CreateLabel("profile_score_lbl", "Profile Score:", 20, 252, clrGray, 10, "Consolas");
   CreateLabel("profile_score_val", "---", 150, 252, clrWhite, 10, "Consolas");

   CreateLabel("status_lbl", "Status:", 20, 269, clrGray, 10, "Consolas");
   CreateLabel("status_val", "ACTIVE", 150, 269, clrLime, 10, "Consolas");

   CreateLabel("halt_lbl", "", 20, 286, clrRed, 10, "Consolas");

   // Separator
   CreateLabel("sep4", "─────────────────────────", 20, 305, clrDimGray, 10, "Consolas");

   // News section
   CreateLabel("news_title", "⚠ ECONOMIC NEWS", 20, 320, clrGold, 10, "Consolas");
   CreateLabel("news_line1", "---", 20, 337, clrSilver, 9, "Consolas");
   CreateLabel("news_line2", "---", 20, 352, clrSilver, 9, "Consolas");
   CreateLabel("news_line3", "---", 20, 367, clrSilver, 9, "Consolas");
   CreateLabel("news_warning", "", 20, 384, clrRed, 10, "Consolas");

   // Separator
   CreateLabel("sep5", "─────────────────────────", 20, 402, clrDimGray, 10, "Consolas");

   // Footer
   CreateLabel("footer", "AIEA Trader v0.0.1", 20, 417, clrDimGray, 8, "Consolas");
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

   UpdateLabel("equity_val", DoubleToString(equity, 2));
   UpdateLabel("balance_val", DoubleToString(balance, 2));
   UpdateLabel("dd_val", StringFormat("%.1f%%", drawdown),
               (drawdown > 10.0 ? clrRed : (drawdown > 5.0 ? clrYellow : clrLime)));

   double dailyPnL = m_riskManager.GetDailyProfit();
   UpdateLabel("daily_pnl_val", DoubleToString(dailyPnL, 2),
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
      UpdateLabel("exp_val", DoubleToString(exp, 2),
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
      UpdateLabel("halt_lbl", "", clrBlack);
   }

   // === NEWS SECTION ===
   if(m_newsManager != NULL)
   {
      string display = m_newsManager.GetNewsDisplayString();
      string lines[5];
      int numLines = StringSplit(display, (ushort)'\n', lines);

      UpdateLabel("news_line1", (numLines > 0 ? lines[0] : "---"), clrSilver);
      UpdateLabel("news_line2", (numLines > 1 ? lines[1] : "---"), clrSilver);
      UpdateLabel("news_line3", (numLines > 2 ? lines[2] : "---"), clrSilver);

      // Warning banner
      string warning = m_newsManager.GetWarningMessage();
      if(warning != "")
      {
         UpdateLabel("news_warning", warning, clrRed);
      }
      else
      {
         UpdateLabel("news_warning", "", clrBlack);
      }

      // Protection status
      string protStatus = m_newsManager.GetProtectionStatus();
      if(protStatus != "")
         UpdateLabel("news_warning", protStatus, clrOrange);
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
