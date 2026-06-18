package dev.u9g.minecraftdatagenerator.generators;

import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMap;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.Registry;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.tags.BlockTags;
import net.minecraft.tags.TagKey;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

import java.util.*;
import java.util.function.Predicate;
import java.util.stream.Collectors;

//TODO entire idea of linking materials to tool speeds is obsolete and just wrong now,
//TODO but we kinda have to support it to let old code work for computing digging times,
//TODO so for now we will handle materials as "virtual" ones based on which tools can break blocks
public class MaterialsDataGenerator implements IDataGenerator {

    private static final List<ImmutableList<String>> COMPOSITE_MATERIALS = ImmutableList.<ImmutableList<String>>builder()
            .add(ImmutableList.of("plant", makeMaterialNameForTag(BlockTags.MINEABLE_WITH_AXE)))
            .add(ImmutableList.of("gourd", makeMaterialNameForTag(BlockTags.MINEABLE_WITH_AXE)))
            .add(ImmutableList.of(makeMaterialNameForTag(BlockTags.LEAVES), makeMaterialNameForTag(BlockTags.MINEABLE_WITH_HOE)))
            .add(ImmutableList.of(makeMaterialNameForTag(BlockTags.LEAVES), makeMaterialNameForTag(BlockTags.MINEABLE_WITH_AXE), makeMaterialNameForTag(BlockTags.MINEABLE_WITH_HOE)))
            .add(ImmutableList.of("vine_or_glow_lichen", "plant", makeMaterialNameForTag(BlockTags.MINEABLE_WITH_AXE)
            )).build();

    private static final Map<String, Float> TOOL_SPEEDS = new HashMap<>() {{
        // Base speeds for each tool type
        put("wooden", 2.0f);
        put("stone", 4.0f);
        put("iron", 6.0f);
        put("diamond", 8.0f);
        put("netherite", 9.0f);
        put("golden", 12.0f);
    }};

    private static Float getToolSpeed(Item item) {
        String itemName = item.toString().toLowerCase();
        // Remove minecraft: prefix if present
        if (itemName.startsWith("minecraft:")) {
            itemName = itemName.substring("minecraft:".length());
        }
        for (Map.Entry<String, Float> entry : TOOL_SPEEDS.entrySet()) {
            if (itemName.startsWith(entry.getKey())) {
                return entry.getValue();
            }
        }
        return 1.0f;
    }

    private static String makeMaterialNameForTag(TagKey<Block> tag) {
        return tag.location().getPath();
    }

    private static void createCompositeMaterialInfo(List<MaterialInfo> allMaterials, List<String> combinedMaterials) {
        String compositeMaterialName = String.join(";", combinedMaterials);

        List<MaterialInfo> mappedMaterials = combinedMaterials.stream()
                .map(otherName -> allMaterials.stream()
                        .filter(other -> other.getMaterialName().equals(otherName))
                        .findFirst().orElseThrow(() -> new RuntimeException("Material not found with name " + otherName)))
                .collect(Collectors.toList());

        Predicate<BlockState> compositePredicate = blockState ->
                mappedMaterials.stream().allMatch(it -> it.getPredicate().test(blockState));

        MaterialInfo materialInfo = new MaterialInfo(compositeMaterialName, compositePredicate).includes(mappedMaterials);
        allMaterials.addFirst(materialInfo);
    }

    private static void createCompositeMaterial(Map<String, Map<Item, Float>> allMaterials, List<String> combinedMaterials) {
        String compositeMaterialName = String.join(";", combinedMaterials);

        Map<Item, Float> resultingToolSpeeds = new LinkedHashMap<>();
        combinedMaterials.stream()
                .map(allMaterials::get)
                .forEach(resultingToolSpeeds::putAll);
        allMaterials.put(compositeMaterialName, resultingToolSpeeds);
    }

    public static List<MaterialInfo> getGlobalMaterialInfo() {
        ArrayList<MaterialInfo> resultList = new ArrayList<>();

        resultList.add(new MaterialInfo("vine_or_glow_lichen", blockState -> blockState.is(Blocks.VINE) || blockState.is(Blocks.GLOW_LICHEN)));
        resultList.add(new MaterialInfo("coweb", blockState -> blockState.is(Blocks.COBWEB)));

        resultList.add(new MaterialInfo("leaves", blockState -> blockState.is(BlockTags.LEAVES)));
        resultList.add(new MaterialInfo("wool", blockState -> blockState.is(BlockTags.WOOL)));

        // Block Materials were removed in 1.20 in favor of block tags
        resultList.add(new MaterialInfo("gourd", blockState -> blockState.is(Blocks.MELON) || blockState.is(Blocks.PUMPKIN) || blockState.is(Blocks.JACK_O_LANTERN)));
        // 'sword_efficient' tag is for all plants, and includes everything from the old PLANT and REPLACEABLE_PLANT materials (see https://minecraft.fandom.com/wiki/Tag#Blocks)
        resultList.add(new MaterialInfo("plant", blockState -> blockState.is(BlockTags.SWORD_EFFICIENT)));

        HashSet<String> uniqueMaterialNames = new HashSet<>();

        Registry<Item> itemRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.ITEM);
        itemRegistry.forEach(item -> {
            if (item.components().get(DataComponents.TOOL) != null) {
                item.components().get(DataComponents.TOOL).rules()
                        .stream().map(rule -> rule.blocks())
                        .forEach(blocks -> {
                            Optional<TagKey<Block>> tagKey = blocks.unwrapKey();
                            if (tagKey.isPresent()) {
                                String materialName = makeMaterialNameForTag((tagKey.get()));

                                if (!uniqueMaterialNames.contains(materialName)) {
                                    uniqueMaterialNames.add(materialName);
                                    resultList.add(new MaterialInfo(materialName, blockState -> blockState.is(blocks)));
                                }
                            }
                        });
            }
        });

        COMPOSITE_MATERIALS.forEach(values -> createCompositeMaterialInfo(resultList, values));
        return resultList;
    }

    @Override
    public String getDataName() {
        return "materials";
    }

    @Override
    public JsonElement generateDataJson() {
        Registry<Item> itemRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.ITEM);

        Map<String, Map<Item, Float>> materialMiningSpeeds = new LinkedHashMap<>();
        materialMiningSpeeds.put("default", new LinkedHashMap<>());

        //Special materials used for shears and swords special mining speed logic
        Map<Item, Float> leavesMaterialSpeeds = new LinkedHashMap<>();
        Map<Item, Float> cowebMaterialSpeeds = new LinkedHashMap<>();
        Map<Item, Float> plantMaterialSpeeds = new LinkedHashMap<>();
        Map<Item, Float> gourdMaterialSpeeds = new LinkedHashMap<>();

        materialMiningSpeeds.put(makeMaterialNameForTag(BlockTags.LEAVES), leavesMaterialSpeeds);
        materialMiningSpeeds.put("coweb", cowebMaterialSpeeds);
        materialMiningSpeeds.put("plant", plantMaterialSpeeds);
        materialMiningSpeeds.put("gourd", gourdMaterialSpeeds);

        //Shears need special handling because they do not follow normal rules like tools
        leavesMaterialSpeeds.put(Items.SHEARS, 15.0f);
        cowebMaterialSpeeds.put(Items.SHEARS, 15.0f);

        Map<Item, Float> vineOrGlowLichenSpeeds = new LinkedHashMap<>();
        vineOrGlowLichenSpeeds.put(Items.SHEARS, 2.0f);
        materialMiningSpeeds.put("vine_or_glow_lichen", vineOrGlowLichenSpeeds);

        Map<Item, Float> woolSpeeds = new LinkedHashMap<>();
        woolSpeeds.put(Items.SHEARS, 5.0f);
        materialMiningSpeeds.put("wool", woolSpeeds);

        itemRegistry.forEach(item -> {
            //Tools are handled rather easily and do not require anything else
            if (item.components().get(DataComponents.TOOL) != null) {
                item.components().get(DataComponents.TOOL).rules()
                        .stream().map(rule -> rule.blocks())
                        .forEach(blocks -> {
                                    Optional<TagKey<Block>> tagKey = blocks.unwrapKey();
                                    if (tagKey.isPresent()) {
                                        String materialName = makeMaterialNameForTag(tagKey.get());

                                        Map<Item, Float> materialSpeeds = materialMiningSpeeds.computeIfAbsent(materialName, k -> new LinkedHashMap<>());
                                        float baseSpeed = getToolSpeed(item);
                                        materialSpeeds.put(item, baseSpeed);
                                    }
                                }
                        );

                //Swords require special treatment
                if (itemRegistry.getKey(item).getPath().contains("sword")) {
                    cowebMaterialSpeeds.put(item, 15.0f);
                    plantMaterialSpeeds.put(item, 1.5f);
                    leavesMaterialSpeeds.put(item, 1.5f);
                    gourdMaterialSpeeds.put(item, 1.5f);
                }
            }});

        COMPOSITE_MATERIALS.forEach(values -> createCompositeMaterial(materialMiningSpeeds, values));

        JsonObject resultObject = new JsonObject();

        for (var entry : materialMiningSpeeds.entrySet()) {
            JsonObject toolSpeedsObject = new JsonObject();

            for (var toolEntry : entry.getValue().entrySet()) {
                int rawItemId = itemRegistry.getId(toolEntry.getKey());
                toolSpeedsObject.addProperty(Integer.toString(rawItemId), toolEntry.getValue());
            }
            resultObject.add(entry.getKey(), toolSpeedsObject);
        }

        return resultObject;
    }

    public static class MaterialInfo {
        private final String materialName;
        private final Predicate<BlockState> predicate;
        private final List<MaterialInfo> includedMaterials = new ArrayList<>();

        public MaterialInfo(String materialName, Predicate<BlockState> predicate) {
            this.materialName = materialName;
            this.predicate = predicate;
        }

        protected MaterialInfo includes(List<MaterialInfo> otherMaterials) {
            this.includedMaterials.addAll(otherMaterials);
            return this;
        }

        public String getMaterialName() {
            return materialName;
        }

        public Predicate<BlockState> getPredicate() {
            return predicate;
        }

        public boolean includesMaterial(MaterialInfo materialInfo) {
            return includedMaterials.contains(materialInfo);
        }

        @Override
        public String toString() {
            return materialName;
        }
    }
}
