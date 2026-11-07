function inspectRoot(id) {
  return Get(id, (n,c) => {
    const {children,...attrs}=n;
    return {...attrs,bounds:{x:n.x,y:n.y,width:n.width,height:n.height},parentId:c.parentCtx?.node.id};
  });
}
function glassStyle(opaque) {
  return {
    fill:opaque?'#17313E':{type:'gradient',gradientType:'linear',rotation:180,colors:[{color:'#E7F5F521',position:0},{color:'#C4E3EF19',position:.5},{color:'#AFCBDC21',position:1}]},
    stroke:opaque?'#B5C4CC':'#BCE0E54A',strokeWidth:.75,
    effect:opaque?[]:[{type:'background_blur',radius:16},{type:'shadow',shadowType:'inner',color:'#F2F6F50D',offset:{x:0,y:1},blur:2}]
  };
}
function syncRoot(record, stars) {
  const id=record.id;
  if(typeof LUMA_ALLOWED==='undefined'||LUMA_ALLOWED[id]!==record.source||id===record.source)throw new Error('Target manifest guard failed');
  if(stars.length!==16||stars.some(s=>s.x<0||s.x>1||s.y<0||s.y>1||s.opacity<0||s.opacity>1))throw new Error('Exactly 16 valid production stars required');
  const before=inspectRoot(id);
  const root=before[0];
  const byId=new Map(before.map(n=>[n.id,n]));
  const home=record.family==='R02'||before.some(n=>n.name==='Connection content');
  const connected=before.some(n=>n.name==='Connection state'&&/VPN подключ[её]н|^Подключено/.test(n.content||''));
  const opaque=id==='b2r9G';
  const changed=[];
  function update(n,p) {Update(n.id,p);changed.push(n.id);}
  function inToolbar(n) {let p=byId.get(n.parentId);const seen=new Set([n.id]);while(p&&!seen.has(p.id)){seen.add(p.id);if(/^(Navigation|AppBar) ·/.test(p.name||''))return true;p=byId.get(p.parentId)}return false;}
  update(root,{name:root.name.replace(/^Blizzard Aurora/,'luma').replace(/ · Косметика/g,''),context:'Current luma implementation, 2026-10-25. Editable static canvas interpretation. SF Pro and UIKit refraction are verified in app captures; canvas uses Inter and a static material preview.',metadata:{...root.metadata,runtimeSync:'2026-10-25',referenceBuild:'0.0.1 (26)',sourceScope:'current-Dart-and-UIKit'}});
  for(const n of before) {
    if(n.type==='text'&&typeof n.content==='string') {
      let content=n.content;
      if(/^(Brand title|App name|App title|Wordmark)$/.test(n.name||'')||(record.family==='D11'&&/message|description|body|сообщен|текст/i.test(n.name||'')&&/новая версия|новую версию|new version/i.test(content)))content=content.replace(/Blizzard(?: VPN)?/g,'luma');
      if(/Version|Версия/i.test(n.name||''))content=content.replace(/0\.0\.1 \(24\)/g,'0.0.1 (26)');
      if(content!==n.content)update(n,{content});
      if(n.name==='Brand title')update(n,{textGrowth:'auto',fontSize:22,fontWeight:'600'});
      if(/^Version24$/.test(n.name||''))update(n,{name:'Current QA version',textGrowth:'auto',fontSize:14,fill:'#F2F6F5'});
    }
    if(n.name==='Version badge')update(n,{width:'fit_content',height:'fit_content',padding:[1,4],fill:'#17313E',cornerRadius:4});
    if(/^Navigation · Blizzard/.test(n.name||''))update(n,{name:'Navigation · luma',padding:[0,8,0,16]});
    if(['Aurora · approved calm atmosphere','luma · single current Aurora glow','luma · quiet backdrop'].includes(n.name)) {
      const secondary=['R04','R12','R13'].includes(record.family);
      update(n,{name:home?'luma · single current Aurora glow':'luma · quiet backdrop',enabled:!secondary,fill:{type:'image',url:'../../../Documents/KVN/design-assets/luma-v01/current-runtime-2026-10-25/luma-aurora-'+(home?(id==='o0Byx'?'phase000':'phase084'):'quiet')+'.png',mode:'stretch'}});
    }
    if(n.fill?.type==='shader'&&/vortex|wave|snowfall/i.test(n.fill.url||''))update(n,{enabled:false});
    if(n.type==='frame'&&inToolbar(n)&&byId.get(n.parentId)?.name!=='luma · Shared toolbar actions'&&(n.metadata?.role==='IconButton'||/^(Quick settings|Add profile|Back|Назад|Close|Toolbar action)$/.test(n.name||'')))update(n,{...glassStyle(opaque),width:48,height:48,cornerRadius:24,context:'Standard existing action, 48pt target. Shared clear UIKit material in app; static canvas preview.'});
    if(n.type==='frame'&&/Connection · UIGlassEffect/.test(n.name||''))update(n,{...glassStyle(opaque),name:'Connection · UIButton clearGlass · static preview',cornerRadius:74,context:'Actual app: one direct UIButton.Configuration.clearGlass, 148×148 circle; no outer manual glass wrapper. Static canvas approximation.'});
    if(n.fill?.type==='image'&&typeof n.fill.url==='string') {
      let url=n.fill.url;
      if(/Quick settings symbol|Add profile symbol/.test(n.name||''))url=url.replace('--secondary.png','--primary.png');
      if(n.name==='Power symbol')url=url.replace(/--(accent|primary|secondary)\.png$/,'--'+(connected?'accent':'primary')+'.png');
      if(/Настройки symbol/.test(n.name||''))url=url.replace('--secondary.png','--primary.png');
      if(url!==n.fill.url)update(n,{fill:{...n.fill,url}});
    }
  }
  if(home) {
    const layers=Get(id,{depth:1}).children.filter(n=>n.name==='luma · 16 static stars');
    const layer=layers[0]?.id||Insert(id,{type:'frame',name:'luma · 16 static stars',layout:'none',layoutPosition:'absolute',x:0,y:0,width:root.bounds.width,height:root.bounds.height,metadata:{type:'runtime-static-decoration',count:16,source:'BlizzardStaticStarsPainter'}});
    for(const extra of layers.slice(1))Update(extra.id,{enabled:false});
    Update(layer,{enabled:true});
    const children=Get(layer,{depth:1}).children||[];
    for(let i=0;i<stars.length;i++){
      const s=stars[i],name='Static star '+(i+1);
      const data={type:'ellipse',name,x:s.x*root.bounds.width-.7,y:s.y*root.bounds.height-.7,width:1.4,height:1.4,fill:'#B3D4D9',opacity:s.opacity,effect:{type:'blur',radius:.7},enabled:true};
      const matches=children.filter(n=>n.name===name);
      if(matches[0]){const {type,...props}=data;Update(matches[0].id,props);}else Insert(layer,data);
      for(const duplicate of matches.slice(1))Update(duplicate.id,{enabled:false});
    }
    for(const extra of children.filter(n=>!/^Static star (?:[1-9]|1[0-6])$/.test(n.name||'')))Update(extra.id,{enabled:false});
    Move(layer,id,1);
    if(Get(layer,{depth:1}).children.filter(n=>n.enabled!==false).length!==16)throw new Error('Static star reconciliation incomplete');
  }
  syncToolbars(record,opaque);
  const afterSources=new Set(inspectRoot(id).map(n=>n.metadata?.sourceElement).filter(Boolean));
  if(before.some(n=>n.metadata?.sourceElement&&!afterSources.has(n.metadata.sourceElement)))throw new Error('Original source element removed from target');
  Update(id,{metadata:{...root.metadata,runtimeSync:'2026-10-25',syncComplete:true,referenceBuild:'0.0.1 (26)',sourceScope:'current-Dart-and-UIKit'}});
  return {id,home,connected,changed:changed.length,elementCount:before.length,bounds:root.bounds,beforeTexts:before.filter(n=>n.type==='text').map(n=>({id:n.id,content:n.content})),sourceElements:before.filter(n=>n.metadata?.sourceElement).map(n=>({id:n.id,source:n.metadata.sourceElement,type:n.type,enabled:n.enabled}))};
}

function syncToolbars(record,opaque) {
  const nodes=inspectRoot(record.id);
  const byId=new Map(nodes.map(n=>[n.id,n]));
  for(const bar of nodes.filter(n=>n.type==='frame'&&/^(Navigation|AppBar) ·/.test(n.name||''))) {
    const children=Get(bar.id,{depth:1}).children||[];
    const back=children.find(n=>/^(Back|Назад|Close)$/.test(n.name||''));
    const title=children.find(n=>n.type==='text');
    if(title)Update(title.id,{width:'fill_container',textGrowth:'fixed-width-height'});
    if(back){Update(back.id,{...glassStyle(opaque),width:48,height:48,cornerRadius:24});Update(bar.id,{padding:[0,8,0,4],gap:20});}
    else Update(bar.id,{padding:[0,8,0,16],gap:8});
    if(record.family==='R12') {
      const existingGroup=children.find(n=>n.name==='luma · Shared toolbar actions');
      const nested=existingGroup?Get(existingGroup.id,{depth:1}).children||[]:[];
      const actions=[...children,...nested].filter(n=>n.type==='frame'&&n.metadata?.role==='IconButton'&&n.id!==back?.id);
      if(actions.length!==3)throw new Error('Expected three original diagnostic actions');
      if(actions.length===3) {
        const group=existingGroup?.id||Insert(bar.id,{type:'frame',name:'luma · Shared toolbar actions',height:48,width:'fit_content',cornerRadius:24,layout:'horizontal',gap:0,alignItems:'center',...glassStyle(opaque),metadata:{type:'runtime-action-group',source:'blizzardToolbarActions',actions:3}});
        for(const action of actions) {
          Update(action.id,{fill:'#00000000',stroke:'#00000000',effect:[],width:48,height:48,cornerRadius:0});
          Move(action.id,group);
        }
        if(Get(group,{depth:1}).children.filter(n=>n.enabled!==false).length!==3)throw new Error('Diagnostic group incomplete');
      }
    }
    if(record.family==='R05') {
      const existingMenu=children.find(n=>n.name==='luma · Settings menu');
      if(existingMenu||!children.some(n=>n.metadata?.role==='IconButton')) {
        const menu=existingMenu?.id||Insert(bar.id,{type:'frame',name:'luma · Settings menu',width:48,height:48,cornerRadius:24,justifyContent:'center',alignItems:'center',...glassStyle(opaque),metadata:{type:'runtime-action',action:'existing-settings-menu'}});
        if(!(Get(menu,{depth:1}).children||[]).some(n=>n.name==='Existing settings overflow'))Insert(menu,{type:'icon',name:'Existing settings overflow',library:'lucide',icon:'ellipsis',width:24,height:24,fill:'#F2F6F5'});
      }
    }
    if(record.family==='R04'&&!/Загрузка|Ошибка/.test(nodes[0].name||'')) {
      const existing=nodes.find(n=>n.type==='text'&&/^(Сохранить|Save)$/.test(n.content||'')&&isInside(n,bar.id));
      if(!existing) {
        const enabled=record.id==='Wuhqa';
        const color=enabled?'#F2F6F5':'#748A94';
        for(const n of children.filter(n=>n.name==='Toolbar end inset'))Update(n.id,{enabled:false});
        const partial=children.find(n=>/luma · Save action/.test(n.name||''));
        const save=partial?.id||Insert(bar.id,{type:'frame',name:'luma · Save action · '+(enabled?'enabled':'disabled'),width:'fit_content',height:48,padding:[0,12],gap:8,alignItems:'center',cornerRadius:24,...glassStyle(opaque),metadata:{type:'runtime-action',action:'existing-save',enabled,source:'ProfileDetailsPage'}});
        const saveChildren=Get(save,{depth:1}).children||[];
        if(!saveChildren.some(n=>n.name==='Save check'))Insert(save,{type:'icon',name:'Save check',library:'lucide',icon:'check',width:24,height:24,fill:color});
        if(!saveChildren.some(n=>n.name==='Save label'))Insert(save,{type:'text',name:'Save label',content:'Сохранить',fontFamily:'Inter',fontSize:14,fontWeight:'500',fill:color});
      } else {
        let owner=byId.get(existing.parentId);
        while(owner&&owner.parentId!==bar.id)owner=byId.get(owner.parentId);
        if(owner)Update(owner.id,{...glassStyle(opaque),height:48,cornerRadius:24});
      }
    }
    if(record.family==='R13') {
      for(const action of children.filter(n=>n.id!==back?.id&&/^(Toolbar action|More|About menu)$/.test(n.name||''))) {
        const icon=Get(action.id,{depth:1}).children?.find(n=>n.type==='rectangle'||n.type==='icon');
        if(icon&&!(icon.type==='icon'&&icon.library==='lucide'&&icon.icon==='ellipsis'))Replace(icon.id,{type:'icon',name:'Existing About menu · ellipsis',library:'lucide',icon:'ellipsis',width:24,height:24,fill:'#F2F6F5',metadata:icon.metadata});
      }
    }
  }
  if(record.family==='R13') {
    for(const mark of nodes.filter(n=>n.metadata?.role==='BrandMarkSlot')) {
      const children=Get(mark.id,{depth:1}).children||[];
      for(const c of children)Update(c.id,{enabled:false});
      Update(mark.id,{width:64,height:64,cornerRadius:0,fill:{type:'image',url:'../../../Documents/KVN/design-assets/luma-v01/current-runtime-2026-10-25/hiddify-upstream-logo.png',mode:'contain'},stroke:'#00000000',effect:[],context:'Existing upstream logo asset, retained in the current app; app name is luma.'});
    }
  }
  function isInside(n,id) {let p=byId.get(n.parentId);const seen=new Set([n.id]);while(p&&!seen.has(p.id)){seen.add(p.id);if(p.id===id)return true;p=byId.get(p.parentId)}return false;}
}
